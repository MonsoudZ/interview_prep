#!/usr/bin/env python3
"""Pull review packets into the Studio, infer locally, return evidence for server validation."""
import argparse
import json
import os
from pathlib import Path
import signal
import sys
import threading
import uuid
from provider import Ollama, ReviewError, check_origin, request, PROMPT_VERSION

def canonical_uuid(value):
    try: return isinstance(value,str) and str(uuid.UUID(value))==value
    except ValueError: return False

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--url',default='http://127.0.0.1:3100')
    parser.add_argument('--ollama',default='http://127.0.0.1:11434')
    parser.add_argument('--model',required=True)
    parser.add_argument('--context',type=int,default=32768)
    parser.add_argument('--worker-id',required=True)
    parser.add_argument('--once',action='store_true')
    parser.add_argument('--doctor',action='store_true')
    args=parser.parse_args()
    base=check_origin(args.url)
    if str(uuid.UUID(args.worker_id))!=args.worker_id: raise ValueError('Use a canonical worker UUID')
    model=Ollama(args.ollama,args.model,args.context)
    digest=model.digest()
    if args.doctor:
        print(json.dumps({'ready':True,'provider':'local_ollama','model':args.model,'model_digest':digest,'context':args.context}));return
    key=os.environ.get('INTERVIEW_REVIEW_BRIDGE_KEY','')
    if len(key.encode())<32: raise ValueError('Configure the private review bridge key')
    stopping=threading.Event()
    for number in (signal.SIGINT,signal.SIGTERM): signal.signal(number,lambda *_:stopping.set())
    state=Path(__file__).parent/'.state'
    state.mkdir(parents=True,exist_ok=True,mode=0o700)
    def heartbeat():
        request(base,'/internal/reviews/heartbeat',{'worker_id':args.worker_id,'model':args.model,'model_digest':digest},key)
    def deliver(path):
        result=json.loads(path.read_text())
        try:
            request(base,'/internal/reviews/'+result['id']+'/result',result,key)
            path.unlink()
        except ReviewError as error:
            if error.http_status in (404,409):
                path.rename(path.with_name(path.name.replace('delivery-','rejected-',1)))
            else: raise
    while not stopping.is_set():
        try:
            for pending in sorted(state.glob('delivery-*.json')): deliver(pending)
            if model.digest()!=digest: raise ReviewError('model_changed')
            heartbeat()
            leased=request(base,'/internal/reviews/lease',{'worker_id':args.worker_id},key)
            if leased.get('job'):
                job=leased['job']
                if not canonical_uuid(job.get('id')): raise ValueError('Control plane sent a non-canonical review id; refusing to use it in a path or URL')
                finished=threading.Event()
                def keep_alive():
                    while not finished.wait(15):
                        try: heartbeat()
                        except Exception: pass
                thread=threading.Thread(target=keep_alive,daemon=True);thread.start()
                result={'id':job['id'],'revision':job['revision'],'prompt_version':job['prompt_version'],
                  'lease_token':leased['lease_token'],'model':args.model,'model_digest':digest}
                try:
                    if job['prompt_version'] != PROMPT_VERSION or job['input'].get('prompt_version') != PROMPT_VERSION:
                        raise ReviewError('output_invalid')
                    report,usage=model.review(job['input'],digest)
                    result.update(status='completed',report=report,usage=usage)
                except ReviewError as error: result.update(status='failed',error_code=str(error))
                except Exception: result.update(status='failed',error_code='worker_interrupted')
                finally: finished.set();thread.join(timeout=16)
                path=state/('delivery-'+job['id']+'.json')
                with os.fdopen(os.open(path,os.O_WRONLY|os.O_CREAT|os.O_EXCL,0o600),'w') as stream:
                    json.dump(result,stream);stream.flush();os.fsync(stream.fileno())
                deliver(path)
                print(json.dumps({'review_id':job['id'],'status':result['status']}),flush=True)
            if args.once:return
        except Exception:
            if args.once: raise
            print('Review worker waiting for app/model connection; no successful review inferred.',file=sys.stderr,flush=True)
        stopping.wait(5)

if __name__=='__main__':
    try:main()
    except Exception:
        print('Review worker unavailable. Check the local model and private app connection.',file=sys.stderr)
        sys.exit(2)
