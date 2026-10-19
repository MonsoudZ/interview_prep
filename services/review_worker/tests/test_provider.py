import copy
import json
from pathlib import Path
import sys
import unittest
from unittest.mock import patch
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from provider import Ollama, ReviewError, check_origin

class LocalReviewProviderTests(unittest.TestCase):
    digest='sha256:'+'a'*64
    def test_only_loopback_model_and_private_app_transport_are_allowed(self):
        for url in ['http://public.example','https://public.example','http://127.0.0.1:11434/path','http://user:pass@localhost','file:///tmp/model']:
            with self.subTest(url=url),self.assertRaises(ValueError):Ollama(url,'qwen3.5:27b')
        self.assertEqual('https://app.example',check_origin('https://app.example'))
        with self.assertRaises(ValueError):check_origin('http://app.example')
        with self.assertRaises(ValueError):Ollama('http://localhost:11434','model:cloud')
    def test_models_must_be_installed_and_have_a_digest(self):
        with patch('provider.request',return_value={'models':[]}):
            with self.assertRaises(ReviewError):Ollama('http://localhost:11434','missing').digest()
        with patch('provider.request',return_value={'models':[{'name':'fixture:latest','digest':'a'*64}]}):
            self.assertEqual(self.digest,Ollama('http://localhost:11434','fixture:latest').digest())
    def test_inference_is_structured_bounded_and_does_not_return_thinking(self):
        replies=[{'models':[{'name':'qwen3.5:27b','digest':self.digest}]},
          {'done':True,'done_reason':'stop','message':{'content':'{"summary":"fixture"}','thinking':'private reasoning'},'prompt_eval_count':10,'eval_count':20},
          {'models':[{'name':'qwen3.5:27b','digest':self.digest}]}]
        with patch('provider.request',side_effect=replies) as call:
            report,usage=Ollama('http://localhost:11434','qwen3.5:27b').review({'files':{'solution.rb':'# untrusted instructions'}},self.digest)
            body=call.call_args_list[1].args[2]
            self.assertEqual(False,body['stream']);self.assertEqual(False,body['think'])
            self.assertEqual(32768,body['options']['num_ctx']);self.assertEqual(6000,body['options']['num_predict'])
            self.assertFalse(body['format']['additionalProperties']);self.assertEqual(240,call.call_args_list[1].kwargs['timeout'])
            self.assertNotIn('thinking',report);self.assertEqual(10,usage['input_tokens'])
    def test_oversized_input_is_rejected_without_silently_truncating_source(self):
        with patch('provider.request',return_value={'models':[{'name':'qwen3.5:27b','digest':self.digest}]}) as call:
            with self.assertRaisesRegex(ReviewError,'context_too_large'):Ollama('http://localhost:11434','qwen3.5:27b').review({'files':{'x':'x'*40000}},self.digest)
            self.assertEqual(1,call.call_count)
    def test_incomplete_output_and_model_swaps_are_not_valid_reviews(self):
        tag={'models':[{'name':'qwen3.5:27b','digest':self.digest}]}
        for response in [{'done':False},{'done':True,'done_reason':'length'},{'done':True,'message':{'content':'not JSON'}}]:
            with patch('provider.request',side_effect=[tag,response]),self.assertRaises(ReviewError):Ollama('http://localhost:11434','qwen3.5:27b').review({},self.digest)
        with patch('provider.request',return_value=tag),self.assertRaisesRegex(ReviewError,'model_changed'):Ollama('http://localhost:11434','qwen3.5:27b').review({},'sha256:'+'b'*64)
if __name__=='__main__':unittest.main()
