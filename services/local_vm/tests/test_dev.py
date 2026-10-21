"""Review-only startup must not require or launch the execution sandbox."""
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import MagicMock, patch

spec = importlib.util.spec_from_file_location('local_dev', Path(__file__).resolve().parents[1] / 'dev.py')
dev = importlib.util.module_from_spec(spec)
spec.loader.exec_module(dev)


class ReviewOnlyStartupTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.state = Path(self.directory.name) / '.state'
        self.config = self.state / 'development.json'
        for name, value in [('STATE', self.state), ('CONFIG', self.config)]:
            replacement = patch.object(dev, name, value)
            replacement.start()
            self.addCleanup(replacement.stop)

    def invoke(self, *args):
        with patch('sys.argv', ['dev.py', *args]):
            dev.main()

    def initialize(self):
        self.invoke('init', '--review-only', '--review-model', 'qwen3.5:27b')

    def test_review_only_configuration_preserves_existing_worker_image_and_keys(self):
        self.invoke('init', '--image', 'sha256:' + 'a' * 64)
        before = json.loads(self.config.read_text())
        self.initialize()
        after = json.loads(self.config.read_text())
        for key in ['image', 'bridge_key', 'signing_key', 'worker_id', 'review_bridge_key', 'review_worker_id']:
            self.assertEqual(before[key], after[key])
        self.assertEqual('qwen3.5:27b', after['review_model'])
        self.assertEqual(0o600, self.config.stat().st_mode & 0o777)

    def test_normal_start_still_requires_real_execution_image(self):
        self.initialize()
        with self.assertRaisesRegex(ValueError, 'Configure a Linux worker image'):
            self.invoke('start')
        with self.assertRaisesRegex(ValueError, 'actual immutable VM image'):
            self.invoke('init', '--review-only', '--image', 'fake')

    def test_review_only_launches_app_and_reviewer_without_execution_bridge(self):
        self.initialize()
        process = MagicMock()
        process.poll.return_value = None
        handlers = {}
        def register(number, callback):
            handlers[number] = callback
        def stop_after_start(_):
            handlers[dev.signal.SIGTERM]()
        with patch.object(dev.socket, 'socket'), patch.object(dev.socket, 'create_connection'), \
             patch.object(dev.signal, 'signal', side_effect=register), \
             patch.object(dev.subprocess, 'Popen', return_value=process) as spawn, \
             patch.object(dev.subprocess, 'run', return_value=MagicMock(returncode=0)) as doctor, \
             patch.object(dev.time, 'sleep', side_effect=stop_after_start):
            self.invoke('start', '--review-only')
        commands = [call.args[0] for call in spawn.call_args_list]
        self.assertEqual(2, len(commands))
        self.assertIn('bin/rails', commands[0])
        self.assertTrue(commands[1][1].endswith('review_worker/worker.py'))
        self.assertIn('--thinking', commands[1], 'reasoning mode is the default for new configurations')
        self.assertIn('--doctor', doctor.call_args.args[0])
        self.assertEqual(spawn.call_args_list[0].kwargs['env']['INTERVIEW_REVIEW_BRIDGE_KEY'],
                         spawn.call_args_list[1].kwargs['env']['INTERVIEW_REVIEW_BRIDGE_KEY'])
        process.terminate.assert_called()
        process.wait.assert_called()

    def test_reasoning_mode_is_stored_at_init_and_overridable_at_start(self):
        self.invoke('init', '--review-only', '--review-model', 'qwen3.5:27b', '--review-thinking', 'off')
        self.assertFalse(json.loads(self.config.read_text())['review_thinking'])
        self.invoke('init', '--review-only', '--review-thinking', 'on')
        self.assertTrue(json.loads(self.config.read_text())['review_thinking'])
        for override, expected in [(None, True), ('off', False), ('on', True)]:
            process = MagicMock()
            process.poll.return_value = None
            handlers = {}
            with patch.object(dev.socket, 'socket'), patch.object(dev.socket, 'create_connection'), \
                 patch.object(dev.signal, 'signal', side_effect=lambda number, callback: handlers.__setitem__(number, callback)), \
                 patch.object(dev.subprocess, 'Popen', return_value=process) as spawn, \
                 patch.object(dev.subprocess, 'run', return_value=MagicMock(returncode=0)), \
                 patch.object(dev.time, 'sleep', side_effect=lambda _: handlers[dev.signal.SIGTERM]()):
                self.invoke('start', '--review-only', *(['--review-thinking', override] if override else []))
            self.assertEqual(expected, '--thinking' in spawn.call_args_list[1].args[0], override)


if __name__ == '__main__':
    unittest.main()
