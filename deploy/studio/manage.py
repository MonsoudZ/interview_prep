#!/usr/bin/env python3
"""Prepare a private central Studio installation; never opens a port or installs software."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import secrets
import shutil
import socket
import sqlite3
import subprocess
import tarfile
import uuid

ROOT=Path(__file__).resolve().parents[2]
CONFIG=ROOT/'services/local_vm/.state/development.json'

def save_config(path, data):
    path.parent.mkdir(parents=True,exist_ok=True,mode=0o700)
    temporary=path.with_suffix('.tmp')
    with os.fdopen(os.open(temporary,os.O_WRONLY|os.O_CREAT|os.O_EXCL,0o600),'w') as stream: json.dump(data,stream)
    temporary.replace(path)

def backup_database(source,destination):
    if not source.is_file(): raise ValueError('No practice database found')
    if destination.exists(): raise ValueError('Choose a new backup filename')
    destination.parent.mkdir(parents=True,exist_ok=True,mode=0o700)
    fd=os.open(destination,os.O_WRONLY|os.O_CREAT|os.O_EXCL,0o600);os.close(fd)
    try:
        with sqlite3.connect('file:'+str(source)+'?mode=ro',uri=True) as incoming, sqlite3.connect(destination) as outgoing:
            incoming.backup(outgoing)
            if outgoing.execute('PRAGMA integrity_check').fetchone()[0]!='ok': raise ValueError('Backup integrity check failed')
    except Exception:
        destination.unlink(missing_ok=True);raise

def restore_database(source,destination):
    if destination.is_file():
        with sqlite3.connect('file:'+str(destination)+'?mode=ro',uri=True) as existing:
            tables={row[0] for row in existing.execute("SELECT name FROM sqlite_master WHERE type='table'")}
            for table in ('accounts','interview_sessions'):
                if table in tables and existing.execute('SELECT count(*) FROM '+table).fetchone()[0]:
                    raise ValueError('Destination already contains practice data; preserve it and reconcile manually')
    with sqlite3.connect('file:'+str(source)+'?mode=ro',uri=True) as incoming:
        if incoming.execute('PRAGMA integrity_check').fetchone()[0]!='ok': raise ValueError('Invalid backup')
        tables={row[0] for row in incoming.execute("SELECT name FROM sqlite_master WHERE type='table'")}
        if not {'accounts','interview_sessions','source_snapshots'}.issubset(tables): raise ValueError('Not an Interview Studio database')
        destination.parent.mkdir(parents=True,exist_ok=True)
        with sqlite3.connect(destination) as outgoing: incoming.backup(outgoing)
        os.chmod(destination,0o600)

EXCLUDED={'.git','.state','.agents','.codex','.aws','.bundle','node_modules','storage','log','tmp','__pycache__','.DS_Store','artifacts','.work','results'}
def package(destination):
    if destination.exists(): raise ValueError('Choose a new package filename')
    roots=['apps/platform','services','curriculum','deploy','docs','experiments/rails-runtime/template','experiments/rails-runtime/reference',
           'experiments/rails-runtime/experiment.py','README.md','.gitignore','.dockerignore']
    def include(info):
        parts=Path(info.name).parts
        if info.issym() or info.islnk() or EXCLUDED.intersection(parts) or any(p=='.env' or p.startswith('.env.') for p in parts): return None
        if any(p.endswith(('.sqlite3','.sqlite3-wal','.sqlite3-shm','.pyc')) for p in parts):return None
        return info
    destination.parent.mkdir(parents=True,exist_ok=True)
    with tarfile.open(destination,'w:gz') as archive:
        for name in roots: archive.add(ROOT/name,arcname='interview-studio/'+name,filter=include)
    digest=hashlib.sha256(destination.read_bytes()).hexdigest()
    destination.with_suffix(destination.suffix+'.sha256').write_text(digest+'  '+destination.name+'\n')
    print('Code-only package created; private configuration, practice data, caches, and secrets excluded.')

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    sub=parser.add_subparsers(dest='command',required=True)
    sub.add_parser('doctor')
    configure=sub.add_parser('configure');configure.add_argument('--image');configure.add_argument('--review-only',action='store_true');configure.add_argument('--model',default='qwen3.5:27b');configure.add_argument('--context',type=int,choices=[32768,65536],default=32768);configure.add_argument('--thinking',choices=['on','off'],default='on')
    backup=sub.add_parser('backup');backup.add_argument('--output',required=True)
    restore=sub.add_parser('restore');restore.add_argument('--from-file',required=True)
    pack=sub.add_parser('package');pack.add_argument('--output',required=True)
    args=parser.parse_args()
    database=ROOT/'apps/platform/storage/development.sqlite3'
    if args.command=='doctor':
        print(json.dumps({'ruby':bool(shutil.which('ruby')),'bundler':bool(shutil.which('bundle')),'colima':bool(shutil.which('colima')),'ollama':bool(shutil.which('ollama')),
          'private_configuration_present':CONFIG.is_file(),'database_present':database.is_file(),'free_disk_gib':round(shutil.disk_usage(ROOT).free/1024**3,1)},indent=2))
    elif args.command=='configure':
        command=['python3',str(ROOT/'services/local_vm/dev.py'),'init','--review-model',args.model,'--review-context',str(args.context)]
        if args.image: command.extend(['--image',args.image])
        if args.review_only: command.append('--review-only')
        command.extend(['--review-thinking',args.thinking])
        subprocess.run(command,check=True)
        data=json.loads(CONFIG.read_text());data.setdefault('app_secret',secrets.token_hex(64));data.setdefault('cookie_name','_interview_studio_'+secrets.token_hex(4));save_config(CONFIG,data)
        print('Private central Studio configuration saved; no model/server/network access started.')
    elif args.command=='backup': backup_database(database,Path(args.output).expanduser().resolve());print('Consistent private practice-data backup created.')
    elif args.command=='restore':
        probe=socket.socket()
        try: probe.bind(('127.0.0.1',3100))
        except OSError: raise ValueError('Stop the local app before restoring practice data')
        finally: probe.close()
        restore_database(Path(args.from_file).expanduser().resolve(),database);print('Practice data restored. Run db:migrate before starting the app.')
    else:package(Path(args.output).expanduser().resolve())

if __name__=='__main__':
    try:main()
    except Exception as error: raise SystemExit(str(error))
