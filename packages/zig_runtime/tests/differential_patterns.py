#!/usr/bin/env python3
"""Seeded structural-pattern recognition/lowering vs pinned morph/editable."""
from pathlib import Path
import argparse, hashlib, json, random, sys
from differential import PACKAGE, ORACLE_SHA, Peer, same, first_difference

def node(code, **fields): return {'0':code, **fields}
def selector(label, name): return node('a', f=node('g',l=name), a=node('v',l=label))
def cases(rng, count):
    for index in range(count):
        label = rng.choice(('$','record','arg','λ'))
        fields = [{'name':rng.choice(('x','y','value','λ')), 'variable':rng.choice(('a','b','x','_','$'))} for _ in range(rng.randrange(5))]
        tail = rng.choice([node('i',v=42),node('v',l=label),node('v',l='a'),node('f',l=label,b=node('v',l=label)),node('l',l=label,v=node('i',v=2),t=node('v',l=label))])
        body = tail
        for f in reversed(fields): body=node('l',l=f['variable'],v=selector(label,f['name']),t=body)
        yield f'gather-{index}', {'op':'gather','label':label,'body':body}
        # Constant bodies avoid unrelated Editable normalization in this helper.
        pattern={'label':label,'destructured':bool(rng.randrange(2)),'fields':fields}
        yield f'lower-{index}', {'op':'lower','pattern':pattern,'body':node('i',v=rng.randrange(-100,100))}

def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--binary',type=Path,default=PACKAGE/'work/patterns-native');p.add_argument('--bun',default='/workspace/tooling/bin/bun');p.add_argument('--seed',type=int,default=20261028);p.add_argument('--cases',type=int,default=1000);p.add_argument('--report',type=Path,default=PACKAGE/'reports/patterns.json');args=p.parse_args()
    native=Peer([str(args.binary.resolve())]);oracle=Peer([args.bun,str(PACKAGE/'tests/patterns_oracle.mjs')]);report={'oracle':ORACLE_SHA,'seed':args.seed,'checked':0,'failed':0,'failures':[],'binary_sha256':hashlib.sha256(args.binary.read_bytes()).hexdigest()}
    try:
        for name,request in cases(random.Random(args.seed),args.cases):
            got=native.request(request);expected=oracle.request(request);report['checked']+=1
            if not same(expected,got):
                report['failed']+=1
                if len(report['failures'])<10:report['failures'].append({'name':name,'request':request,'difference':first_difference(expected,got),'expected':expected,'got':got})
        report['passed']=not report['failed']
    finally:
        native.close();oracle.close();args.report.parent.mkdir(exist_ok=True,parents=True);args.report.write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
    print(json.dumps({k:v for k,v in report.items() if k!='failures'}));return 0 if report.get('passed') else 1
if __name__=='__main__':sys.exit(main())
