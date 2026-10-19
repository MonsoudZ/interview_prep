import importlib.util
from pathlib import Path
import sqlite3
import tarfile
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('studio_manage', Path(__file__).resolve().parents[1] / 'manage.py')
manage = importlib.util.module_from_spec(spec)
spec.loader.exec_module(manage)

class StudioTransferTests(unittest.TestCase):
    def database(self, path, populated=True):
        with sqlite3.connect(path) as db:
            db.execute('PRAGMA journal_mode=WAL')
            for name in ('accounts', 'interview_sessions', 'source_snapshots'):
                db.execute('CREATE TABLE '+name+' (id TEXT)')
            if populated: db.execute("INSERT INTO accounts VALUES ('preserved-account')")

    def test_backup_is_consistent_private_and_restores_without_overwriting_practice(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source, backup, target = [root / name for name in ('source.sqlite3', 'backup.sqlite3', 'target.sqlite3')]
            self.database(source)
            with sqlite3.connect(source) as live:
                live.execute("INSERT INTO source_snapshots VALUES ('saved-submission')")
                live.commit()
                manage.backup_database(source, backup)
            self.assertEqual(0o600, backup.stat().st_mode & 0o777)
            with self.assertRaises(ValueError): manage.backup_database(source, backup)
            self.database(target, populated=False)
            manage.restore_database(backup, target)
            with sqlite3.connect(target) as db:
                self.assertEqual('saved-submission', db.execute('SELECT id FROM source_snapshots').fetchone()[0])
            with self.assertRaisesRegex(ValueError, 'already contains practice'): manage.restore_database(backup, target)

    def test_code_package_omits_private_data_and_symlinks(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            for name in ('apps/platform', 'services', 'curriculum', 'deploy', 'docs',
                         'experiments/rails-runtime/template', 'experiments/rails-runtime/reference'):
                (root / name).mkdir(parents=True)
            for name in ('README.md', '.gitignore', '.dockerignore', 'experiments/rails-runtime/experiment.py',
                         'apps/platform/app.rb', 'services/worker.py'):
                (root / name).write_text('public code')
            for name in ('services/.state/key.json', 'apps/platform/storage/development.sqlite3',
                         'apps/platform/.env.production', 'services/.aws/credentials', 'services/__pycache__/cache.pyc'):
                path = root / name
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text('PRIVATE FIXTURE')
            (root / 'services/private-link').symlink_to(root / 'services/.state/key.json')
            target = root / 'out/code.tar.gz'
            with patch.object(manage, 'ROOT', root): manage.package(target)
            with tarfile.open(target) as archive:
                names = archive.getnames()
                self.assertIn('interview-studio/apps/platform/app.rb', names)
                self.assertFalse(any('private-link' in name or '.state' in name or 'storage' in name or '.env' in name or '.aws' in name for name in names))
                for entry in archive:
                    if entry.isfile(): self.assertNotIn(b'PRIVATE FIXTURE', archive.extractfile(entry).read())
            self.assertTrue(target.with_suffix('.gz.sha256').is_file())

if __name__ == '__main__': unittest.main()
