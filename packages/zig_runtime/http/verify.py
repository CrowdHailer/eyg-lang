#!/usr/bin/env python3
"""Local-only native Fetch / pinned Gleam oracle checks, including verified TLS.
Needs cryptography for temporary test CA generation; never calls a remote URL.
"""
from __future__ import annotations
import argparse,base64,datetime,gzip,hashlib,http.server,json,os,random,select,shutil,socket,ssl,subprocess,sys,threading
from pathlib import Path
ROOT=Path(__file__).resolve().parents[3]
BODY='Hello 🌿 — λ\n'.encode()

class Handler(http.server.BaseHTTPRequestHandler):
 protocol_version='HTTP/1.1'
 other_port=0
 def log_message(self,*args):pass
 def date_time_string(self,timestamp=None):return 'Thu, 01 Jan 1970 00:00:00 GMT'
 def answer(self,status,body=b'',headers=()):
  self.send_response(status)
  for name,value in headers:self.send_header(name,value)
  self.send_header('Content-Length',str(len(body)));self.end_headers()
  if self.command!='HEAD':self.wfile.write(body)
 def do_GET(self):
  if self.path=='/redirect':return self.answer(302,headers=[('Location','/unicode')])
  if self.path=='/redirect-other':return self.answer(302,headers=[('Location',f'http://127.0.0.1:{self.other_port}/echo')])
  if self.path=='/redirect-same':return self.answer(302,headers=[('Location','/echo')])
  if self.path=='/loop':return self.answer(302,headers=[('Location','/loop')])
  if self.path=='/unicode':return self.answer(200,BODY,[('X-Repeat','one'),('X-Repeat','two'),('Set-Cookie','a=1'),('Set-Cookie','b=2')])
  if self.path=='/latin':return self.answer(200,BODY,[('X-Latin','café')])
  if self.path=='/gzip':return self.answer(200,gzip.compress(BODY,mtime=0),[('Content-Encoding','gzip')])
  if self.path.startswith('/echo'):
   content=self.rfile.read(int(self.headers.get('Content-Length','0')))
   value=dict(method=self.command,path=self.path,body=base64.b64encode(content).decode(),authorization=self.headers.get('Authorization'),cookie=self.headers.get('Cookie'),repeat=self.headers.get('X-Repeat'),content_type=self.headers.get('Content-Type'),custom=self.headers.get('X-Value'))
   return self.answer(200,json.dumps(value,sort_keys=True).encode(),[('Content-Type','application/json')])
  return self.answer(404,b'not found')
 def do_TRACE(self):return self.answer(200,BODY,[('X-Trace','yes')])
 def do_HEAD(self):return self.answer(200,BODY,[('X-Head','yes')])
 def do_POST(self):
  if self.path.startswith('/redirect-'):
   self.rfile.read(int(self.headers.get('Content-Length','0')))
   return self.answer(int(self.path.rsplit('-',1)[1]),headers=[('Location','/echo')])
  return self.do_GET()
 do_DELETE=do_POST
 do_OPTIONS=do_POST
 do_PUT=do_POST
 do_PATCH=do_POST
 do_PROPPATCH=do_POST

class Proxy(http.server.BaseHTTPRequestHandler):
 protocol_version='HTTP/1.1'
 accepted=0
 def log_message(self,*args):pass
 def date_time_string(self,timestamp=None):return 'Thu, 01 Jan 1970 00:00:00 GMT'
 def do_CONNECT(self):
  if self.headers.get('Proxy-Authorization')!='Basic dGVzdDpsb2NhbA==':
   self.send_response(407);self.send_header('Content-Length','0');self.end_headers();return
  host,port=self.path.rsplit(':',1)
  if host not in ['localhost','127.0.0.1']:
   self.send_response(403);self.send_header('Content-Length','0');self.end_headers();return
  target=socket.create_connection(('127.0.0.1',int(port)))
  self.send_response(200);self.end_headers();Proxy.accepted+=1
  try:
   while True:
    ready,_,_=select.select([self.connection,target],[],[],5)
    if not ready:break
    for current in ready:
     data=current.recv(65536)
     if not data:return
     (target if current is self.connection else self.connection).sendall(data)
  finally:target.close();self.close_connection=True

class Server:
 def __init__(self,tls=None,handler=Handler):
  self.server=http.server.ThreadingHTTPServer(('127.0.0.1',0),handler);self.server.daemon_threads=True
  if tls:self.server.socket=tls.wrap_socket(self.server.socket,server_side=True)
  self.port=self.server.server_address[1];self.thread=threading.Thread(target=self.server.serve_forever,daemon=True);self.thread.start()
 def close(self):self.server.shutdown();self.server.server_close();self.thread.join()

def string(s):return dict(string=s)
def integer(n):return dict(integer=n)
def record(**kw):return dict(record=kw)
def tagged(label,value=None):return dict(tagged=dict(label=label,value=record() if value is None else value))
def binary(data):return dict(binary={'/':dict(bytes=base64.b64encode(data).decode().rstrip('='))})
def request(port,path='/unicode',method='GET',body=b'',headers=(),query=None,https=False,host='127.0.0.1'):
 return record(method=tagged(method),scheme=tagged('HTTPS' if https else 'HTTP'),host=string(host),port=tagged('Some',integer(port)),path=string(path),query=tagged('None') if query is None else tagged('Some',string(query)),headers=dict(list=[record(key=string(k),value=string(v)) for k,v in headers]),body=binary(body))
def body(response):return base64.b64decode(response['tagged']['value']['record']['body']['binary']['/']['bytes']+'===')
def headers(response):return [(h['record']['key']['string'],h['record']['value']['string']) for h in response['tagged']['value']['record']['headers']['list']]
def run(command,fixture,env=None):
 result=subprocess.run(command,input=json.dumps(fixture),text=True,capture_output=True,timeout=30,env=env,cwd=ROOT)
 assert result.returncode==0,(result.returncode,result.stdout,result.stderr)
 return json.loads(result.stdout)

def make_tls(out):
 from cryptography import x509
 from cryptography.hazmat.primitives import hashes,serialization
 from cryptography.hazmat.primitives.asymmetric import rsa
 from cryptography.x509.oid import NameOID
 import ipaddress
 now=datetime.datetime.now(datetime.timezone.utc)
 key=rsa.generate_private_key(public_exponent=65537,key_size=2048)
 name=x509.Name([x509.NameAttribute(NameOID.COMMON_NAME,'EYG temporary test CA')])
 ca=x509.CertificateBuilder().subject_name(name).issuer_name(name).public_key(key.public_key()).serial_number(x509.random_serial_number()).not_valid_before(now-datetime.timedelta(days=1)).not_valid_after(now+datetime.timedelta(days=2)).add_extension(x509.BasicConstraints(ca=True,path_length=None),critical=True).sign(key,hashes.SHA256())
 leafkey=rsa.generate_private_key(public_exponent=65537,key_size=2048)
 leaf=x509.CertificateBuilder().subject_name(x509.Name([x509.NameAttribute(NameOID.COMMON_NAME,'localhost')])).issuer_name(name).public_key(leafkey.public_key()).serial_number(x509.random_serial_number()).not_valid_before(now-datetime.timedelta(days=1)).not_valid_after(now+datetime.timedelta(days=2)).add_extension(x509.SubjectAlternativeName([x509.DNSName('localhost')]),critical=False).sign(key,hashes.SHA256())
 capath=out/'ca.pem';certpath=out/'server.pem';keypath=out/'server-key.pem'
 capath.write_bytes(ca.public_bytes(serialization.Encoding.PEM));certpath.write_bytes(leaf.public_bytes(serialization.Encoding.PEM));keypath.write_bytes(leafkey.private_bytes(serialization.Encoding.PEM,serialization.PrivateFormat.PKCS8,serialization.NoEncryption()));keypath.chmod(0o600)
 context=ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER);context.load_cert_chain(certpath,keypath)
 return context,capath

def main():
 ap=argparse.ArgumentParser();ap.add_argument('--binary',type=Path,default=ROOT/'work/http-native');ap.add_argument('--skip-oracle',action='store_true');ap.add_argument('--bun',default=os.environ.get('BUN') or shutil.which('bun') or '/workspace/tooling/bin/bun');args=ap.parse_args()
 out=ROOT/'work/http-verification';out.mkdir(parents=True,exist_ok=True);checks=[];unsupported=[]
 oracle_count=0
 native=[str(args.binary.resolve())];oracle=[args.bun,str(ROOT/'packages/zig_runtime/http/oracle.mjs')]
 first=Server();second=Server();Handler.other_port=second.port
 def check(name,fixture,expected=None,compare=True):
  nonlocal oracle_count
  response=run(native,fixture);assert response['tagged']['label']=='Ok',(name,response)
  if expected is not None:assert body(response)==expected,(name,response)
  if compare and not args.skip_oracle:
   reference=run(oracle,fixture);oracle_count+=1
   assert response==reference,(name,response,reference)
  checks.append(name);return response
 try:
  check('GET UTF-8 response, repeated headers, cookies',request(first.port),BODY)
  check('Latin-1 response headers',request(first.port,'/latin'),BODY)
  check('Latin-1 request headers',request(first.port,'/echo',headers=[('X-Value','café')]))
  check('UTF-8 URL path',request(first.port,'/echo/café'))
  check('gzip decompression',request(first.port,'/gzip'),BODY)
  response=check('HTTP error statuses remain successful responses',request(first.port,'/missing'),b'not found');assert response['tagged']['value']['record']['status']==integer(404)
  check('HEAD returns no response bytes',request(first.port,method='HEAD'),b'')
  check('TRACE matches pinned empty response body',request(first.port,method='TRACE'),b'')
  check('CONNECT non-success response is represented',request(first.port,method='CONNECT'))
  check('relative redirects',request(first.port,'/redirect'),BODY)
  response=check('query and existing percent escapes',request(first.port,'/echo',query='q=hello%20world&token=a%2Fb'))
  assert json.loads(body(response))['path']=='/echo?q=hello%20world&token=a%2Fb'
  for method in ['POST','PUT','PATCH','DELETE']:
   response=check(method+' preserves binary body',request(first.port,'/echo',method=method,body=bytes([0,1,127,255]),headers=[('X-Repeat','one'),('X-Repeat','two')]))
   assert base64.b64decode(json.loads(body(response))['body'])==bytes([0,1,127,255])
  check('OPTIONS empty body',request(first.port,'/echo',method='OPTIONS'))
  extension=request(first.port,'/echo',method='POST',body=BODY);extension['record']['method']=tagged('OTHER',string('PROPPATCH'))
  check('long OTHER method remains untruncated',extension)
  response=check('same-origin redirect retains authorization',request(first.port,'/redirect-same',headers=[('Authorization','Bearer test-local'),('Cookie','local=yes')]))
  assert json.loads(body(response))['authorization']=='Bearer test-local'
  response=check('cross-port redirect strips credentials',request(first.port,'/redirect-other',headers=[('Authorization','Bearer test-local'),('Cookie','local=yes')]))
  assert json.loads(body(response))['authorization'] is None and json.loads(body(response))['cookie'] is None
  for status in [301,302,303,307,308]:
   response=check(f'POST redirect {status}',request(first.port,f'/redirect-{status}',method='POST',body=BODY,headers=[('Content-Type','application/octet-stream')]))
   echoed=json.loads(body(response));assert echoed['method']==('POST' if status in [307,308] else 'GET')
   assert base64.b64decode(echoed['body'])==(BODY if status in [307,308] else b'')
  for name,fixture in [('redirect limit',request(first.port,'/loop')),('header injection',request(first.port,headers=[('X-Bad','bad\r\nInjected: yes')])),('invalid port',request(70000)),('OPTIONS body matches oracle rejection',request(first.port,'/echo',method='OPTIONS',body=b'abc')),('non-Latin-1 header rejected',request(first.port,headers=[('X-Emoji','🌿')]))]:
   actual=run(native,fixture);assert actual['tagged']['label']=='Error'
   if not args.skip_oracle:
    observed=run(oracle,fixture)
    if 'oracle_exception' in observed:
     assert name in ['header injection','invalid port','non-Latin-1 header rejected'],(name,observed)
     unsupported.append(dict(case=name,native=actual,oracle=observed,reason='Oracle throws outside the Result contract; native preserves Error result'))
    else:
     assert actual==observed,(name,actual,observed);oracle_count+=1
   checks.append(name)
  closed=Server();closed_port=closed.port;closed.close()
  unreachable=request(closed_port);actual=run(native,unreachable);assert actual['tagged']['label']=='Error'
  if not args.skip_oracle:assert actual==run(oracle,unreachable);oracle_count+=1
  checks.append('closed port error value matches oracle')
  methods=['ACL','BIND','CHECKOUT','COPY','LINK','LOCK','M-SEARCH','MERGE','MKACTIVITY','MKCALENDAR','MKCOL','MOVE','NOTIFY','PROPFIND','PROPPATCH','PURGE','QUERY','REBIND','REPORT','SEARCH','SOURCE','SUBSCRIBE','UNBIND','UNLINK','UNLOCK','UNSUBSCRIBE']
  rng=random.Random(0x455947)
  methods+=['','BAD METHOD','\r\n','λ','ZZZ','X'*1025,'get','purge','x-custom-extension']
  methods+=[''.join(rng.choice('ABCxyz012_! λ\r\n') for _ in range(rng.randrange(1,25))) for _ in range(20)]
  for index,method in enumerate(methods):
   fixture=request(first.port,'/echo');fixture['record']['method']=tagged('OTHER',string(method))
   check(f'OTHER method constructor parity {index}: {method[:24]!r}',fixture)
  raw_get=subprocess.check_output(native+['--get',f'http://127.0.0.1:{first.port}/unicode'],text=True,timeout=30,cwd=ROOT)
  retrieved=json.loads(raw_get);assert retrieved['status']==200 and retrieved['body']==BODY.decode();checks.append('shared GET helper returns owned response')
  context,ca=make_tls(out);tls=Server(context)
  try:
   fixture=request(tls.port,https=True,host='localhost')
   actual=run(native,fixture);assert actual['tagged']['label']=='Error'
   if not args.skip_oracle:assert actual==run(oracle,fixture),(actual,run(oracle,fixture));oracle_count+=1
   checks.append('untrusted TLS certificate error matches oracle')
   trusted=dict(os.environ,SSL_CERT_FILE=str(ca))
   response=run(native,fixture,env=trusted);assert response['tagged']['label']=='Ok' and body(response)==BODY,response;checks.append('HTTPS using configured CA verifies peer')
   mismatch=run(native,request(tls.port,https=True,host='127.0.0.1'),env=trusted);assert mismatch['tagged']['label']=='Error';checks.append('TLS hostname mismatch rejected')
   from cryptography import x509
   from cryptography.hazmat.primitives import serialization
   ca_der=x509.load_pem_x509_certificate(ca.read_bytes()).public_bytes(serialization.Encoding.DER)
   for kind,data in [('PEM',ca.read_bytes()),('DER',ca_der)]:
    directory=out/f'android-{kind.lower()}-roots';directory.mkdir(exist_ok=True)
    (directory/'0123abcd.0').write_bytes(data)
    count=subprocess.check_output(native+['--ca-directory',str(directory)],text=True,timeout=30,cwd=ROOT)
    assert count.strip()=='1',(kind,count);checks.append(f'Android hashed {kind} trust directory decoded')
    directory_trust=dict(os.environ,SSL_CERT_DIR=str(directory))
    actual=run(native,fixture,env=directory_trust)
    assert actual['tagged']['label']=='Ok' and body(actual)==BODY,(kind,actual);checks.append(f'HTTPS verifies with {kind}-only trust directory')

   if not args.skip_oracle:
    trusted_oracle=dict(trusted,NODE_EXTRA_CA_CERTS=str(ca))
    assert run(oracle,fixture,env=trusted_oracle)==response;oracle_count+=1
    expected_mismatch=run(oracle,request(tls.port,https=True,host='127.0.0.1'),env=trusted_oracle)
    assert mismatch==expected_mismatch,(mismatch,expected_mismatch);oracle_count+=1
   proxy=Server(handler=Proxy)
   try:
    # This temporary loopback proxy accepts only the local fixture origin.
    # It tests configured proxy authentication and verified TLS inside CONNECT.
    url=f'http://test:local@127.0.0.1:{proxy.port}'
    proxied=dict(trusted,https_proxy=url,HTTPS_PROXY=url,no_proxy='',NO_PROXY='')
    response=run(native,fixture,env=proxied);assert response['tagged']['label']=='Ok' and body(response)==BODY and Proxy.accepted==1,response;checks.append('authenticated proxy CONNECT upgrades to verified TLS')
    bad=f'http://test:wrong@127.0.0.1:{proxy.port}'
    refused=dict(proxied,https_proxy=bad,HTTPS_PROXY=bad)
    actual=run(native,fixture,env=refused);assert actual['tagged']['label']=='Ok' and actual['tagged']['value']['record']['status']==integer(407) and Proxy.accepted==1
    if not args.skip_oracle:
     observed=run(oracle,fixture,env=refused);assert actual==observed,(actual,observed);oracle_count+=1
    checks.append('proxy rejection matches HTTP407 without direct or plaintext fallback')
   finally:proxy.close()

  finally:tls.close()
  result=dict(passed=not unsupported,transport_checks_passed=True,checks=len(checks),cases=checks,network='loopback HTTP and HTTPS only',oracle_commit='be502aa03df926a8f9df474a0a7fe16c8fb14fbd',binary_sha256=hashlib.sha256(args.binary.read_bytes()).hexdigest(),oracle_runtime=subprocess.check_output([oracle[0],'--version'],text=True).strip() if not args.skip_oracle else None,oracle_compared=not args.skip_oracle,oracle_comparisons=oracle_count,parity_complete=not args.skip_oracle and not unsupported,unsupported_count=len(unsupported),exact_error_mappings=['closed port','untrusted TLS','hostname mismatch','redirect limit','OPTIONS body'],error_strings='Exact mapping checked for closed port, untrusted TLS, hostname mismatch, redirect limit and OPTIONS body; other native errors remain explicit',unsupported=unsupported)
  (out/'result.json').write_text(json.dumps(result,indent=2)+'\n');print(json.dumps(result))
  return 0 if result['passed'] else 1
 finally:first.close();second.close()
if __name__=='__main__':sys.exit(main())
