"""Local-only Ollama transport. Source is model context, never executable instructions."""
import json
from pathlib import Path
import socket
import time
from urllib.error import HTTPError, URLError
from urllib.parse import urlparse
from urllib.request import Request, HTTPRedirectHandler, ProxyHandler, build_opener

ROOT = Path(__file__).parent
SCHEMA = json.loads((ROOT / 'report.schema.json').read_text())
PROMPT = (ROOT / 'prompt.txt').read_text()
PROMPT_VERSION = 'senior-review-v1'

class ReviewError(Exception):
    def __init__(self, code, http_status=None):
        super().__init__(code)
        self.http_status = http_status
class NoRedirect(HTTPRedirectHandler):
    def redirect_request(self, *args, **kwargs):
        raise ReviewError('model_unavailable')

def check_origin(url, local=False):
    p = urlparse(url)
    if p.username or p.password or p.query or p.fragment or p.path not in ('', '/') or not p.hostname:
        raise ValueError('Use an origin without credentials, path, query, or fragment')
    loopback = p.hostname in ('localhost', '127.0.0.1', '::1')
    if (local and not loopback) or p.scheme not in ('http', 'https') or (p.scheme == 'http' and not loopback):
        raise ValueError('Model must be loopback-only; app connections require HTTPS except loopback')
    return url.rstrip('/')

def request(url, path, body=None, key=None, timeout=15, limit=1048576):
    headers = {'Content-Type':'application/json'}
    if key: headers['Authorization'] = 'Bearer '+key
    raw = None if body is None else json.dumps(body, ensure_ascii=True).encode()
    req = Request(url+path, data=raw, headers=headers)
    try:
        with build_opener(NoRedirect(), ProxyHandler({})).open(req, timeout=timeout) as reply:
            data=reply.read(limit+1)
            if len(data)>limit: raise ReviewError('output_invalid')
            return json.loads(data)
    except (TimeoutError, socket.timeout) as error:
        raise ReviewError('inference_timeout') from error
    except HTTPError as error:
        raise ReviewError('model_unavailable', http_status=error.code) from error
    except (URLError, OSError, json.JSONDecodeError) as error:
        raise ReviewError('model_unavailable') from error

class Ollama:
    def __init__(self, url, model, context=32768):
        self.url=check_origin(url,local=True)
        if not model or len(model)>100 or model.endswith((':cloud','-cloud')):
            raise ValueError('Choose an explicitly installed local model')
        if context not in (32768,65536): raise ValueError('Use a bounded 32768 or 65536 token context')
        self.model=model; self.context=context
    def digest(self):
        tags=request(self.url,'/api/tags')
        item=next((m for m in tags.get('models',[]) if m.get('name')==self.model),None)
        if not item: raise ReviewError('model_unavailable')
        digest=item.get('digest','')
        import re
        # Ollama returns the hex digest without a prefix; persist a canonical identity.
        if re.fullmatch(r'[0-9a-f]{64}',digest): digest='sha256:'+digest
        if not re.fullmatch(r'sha256:[0-9a-f]{64}',digest): raise ReviewError('model_unavailable')
        return digest
    def review(self, packet, expected_digest):
        if self.digest()!=expected_digest: raise ReviewError('model_changed')
        content=json.dumps(packet,ensure_ascii=True,separators=(',',':'))
        # Conservative byte budget; fail instead of silently reviewing a truncated submission.
        if len((PROMPT+content).encode())>self.context-6000-2048:
            raise ReviewError('context_too_large')
        started=time.monotonic()
        response=request(self.url,'/api/chat',{'model':self.model,
          'messages':[{'role':'system','content':PROMPT},{'role':'user','content':content}],
          'stream':False,'think':False,'format':SCHEMA,'keep_alive':'5m',
          'options':{'temperature':0,'num_ctx':self.context,'num_predict':6000}}, timeout=240)
        if response.get('done') is not True or response.get('done_reason')=='length': raise ReviewError('output_invalid')
        try: report=json.loads(response['message']['content'])
        except (KeyError,TypeError,json.JSONDecodeError) as error: raise ReviewError('output_invalid') from error
        if not isinstance(report,dict) or len(json.dumps(report).encode())>80000: raise ReviewError('output_invalid')
        if self.digest()!=expected_digest: raise ReviewError('model_changed')
        return report, {'input_tokens':response.get('prompt_eval_count',0),
          'output_tokens':response.get('eval_count',0),'duration_seconds':round(time.monotonic()-started,3)}
