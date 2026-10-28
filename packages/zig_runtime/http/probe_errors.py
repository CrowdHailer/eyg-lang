#!/usr/bin/env python3
"""Print native and actual Gleam host failure values using local fixtures only."""
import json,os
from verify import *
def main():
 out=ROOT/'work/http-verification';out.mkdir(parents=True,exist_ok=True)
 native=[str(ROOT/'work/http-native')];oracle=['/workspace/tooling/bin/bun',str(ROOT/'packages/zig_runtime/http/oracle.mjs')]
 plain=Server();closed=Server();port=closed.port;closed.close();context,ca=make_tls(out);secure=Server(context);proxy=Server(handler=Proxy)
 trust=dict(os.environ,SSL_CERT_FILE=str(ca),NODE_EXTRA_CA_CERTS=str(ca));bad=f'http://test:wrong@127.0.0.1:{proxy.port}';denied=dict(trust,https_proxy=bad,HTTPS_PROXY=bad,no_proxy='',NO_PROXY='')
 invalid=request(plain.port);invalid['record']['method']=tagged('OTHER',string('BAD METHOD'))
 cases=[('closed port',request(port),None),('untrusted TLS',request(secure.port,https=True,host='localhost'),None),('hostname mismatch',request(secure.port,https=True,host='127.0.0.1'),trust),('redirect limit',request(plain.port,'/loop'),None),('invalid header',request(plain.port,headers=[('X-Bad','bad\r\nInjected: yes')]),None),('invalid method',invalid,None),('invalid port',request(70000),None),('proxy denial',request(secure.port,https=True,host='localhost'),denied),('OPTIONS nonempty body',request(plain.port,'/echo',method='OPTIONS',body=b'abc'),None)]
 rows=[]
 try:
  for name,fixture,env in cases:
   actual=run(native,fixture,env=env);expected=run(oracle,fixture,env=env)
   row=dict(name=name,native=actual,oracle=expected);rows.append(row);print(json.dumps(row),flush=True)
  (out/'failure-probe.json').write_text(json.dumps(rows,indent=2)+'\n')
 finally:plain.close();secure.close();proxy.close()
if __name__=='__main__':main()
