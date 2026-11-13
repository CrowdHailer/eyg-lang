#!/usr/bin/env python3
"""Mutate canonical IR fields and compare decoding to the pinned Gleam oracle.

Includes accepted noncanonical encodings as well as malformed input: preserving
an oracle's codec contract includes accepting its aliases and rejecting unsafe
integers before evaluation.
Build the isolated transport without replacing the interactive binary:
  zig build-exe -OReleaseFast --dep eyg_interpreter \
    -Mroot=tests/evaluation_runner.zig -Meyg_interpreter=src/interpreter.zig \
    -femit-bin=work/evaluation-validation
"""
import argparse, base64, copy, hashlib, json, os, random, shutil, subprocess, time
from pathlib import Path
from differential import PACKAGE, ORACLE, ORACLE_SHA, Peer, node, generated_program, same, first_difference


def varint(value, extra=0):
    out = bytearray()
    while value >= 128:
        out.append((value & 127) | 128); value >>= 7
    if extra:
        out.append(value | 128); out.extend([128] * (extra - 1)); out.append(0)
    else: out.append(value)
    return bytes(out)


def cid(raw, padded=False):
    text = base64.b32encode(raw).decode().lower()
    return 'b' + (text if padded else text.rstrip('='))


def cases(rng, count):
    originals = [node('i', v=1), node('s', v='s'), node('v', l='x'), node('z'),
                 node('f', l='x', b=node('v', l='x')), node('l', l='x', v=node('i', v=1), t=node('v', l='x')),
                 node('a', f=node('f', l='x', b=node('v', l='x')), a=node('i', v=1)),
                 node('x', v={'/': {'bytes': 'AQ'}}), node('@', p='standard'), node('.', i='./a.eyg')]
    for tag in ('c','ta','u','n','e','g','o','t','m','p','h','b'):
        originals.append(node(tag, **({} if tag in ('c','ta','u','n') else {'l':'label'})))
    raw = varint(1) + varint(297) + varint(18) + varint(32) + bytes(range(32))
    originals += [node('#', l={'/':cid(raw)}), node('@', p='standard', r=3, l={'/':cid(raw)})]
    for program in originals: yield 'baseline', program
    for base in originals:
        for key in list(base):
            mutated=copy.deepcopy(base); del mutated[key]; yield 'missing-field',mutated
            for value in [None,False,True,1,1.0,1.5,'',[],{},['0']]:
                mutated=copy.deepcopy(base);mutated[key]=value;yield 'field-type',mutated
        mutated=copy.deepcopy(base);mutated['extra']={'garbage':True};yield 'extra-field',mutated
    for number in [0.0,1.0,-0.0,1.5,-9007199254740991,9007199254740991,9007199254740992,9007199254740993,-9007199254740992,9223372036854775807,1e99]:
        yield 'integer-edge', node('i',v=number)
        yield 'version-edge', node('@',p='standard',r=number)
    for encoded in ['', 'AQ', 'AQ==', 'AR', 'AR==', 'A Q\n', '\tAQ\r\n', 'A=', 'A===', '====', 'AAA=', 'AAAA', 'AAAA=', 'AQ-_', 'AQ+/', 'A\vQ', 'A\fQ', 'AA\u00a0', 'AA', 'A', '###', 'Zg=']:
        yield 'base64-edge',node('x',v={'/':{'bytes':encoded}})
    for size in [0,1,2,3,4,5,8,16,32]:
        for codec in [0,85,113,297,2**32-1,2**53,2**63,2**64,2**127,2**128,2**511,2**1023]:
            for extra in [0,1]:
                raw = varint(1,extra)+varint(codec,extra)+varint(18,extra)+varint(size,extra)+bytes([255])*size
                text=cid(raw)
                for alias in [text,'b'+text[1:].upper(),cid(raw,True),cid(raw+b'trailing')]:
                    yield 'cid-alias',node('#',l={'/':alias})
    # Unknown fields and encoding aliases are discarded by decoding even
    # inside function bodies; closure equality exposes that normalization.
    reference=cid(varint(1)+varint(297)+varint(18)+varint(32)+bytes(range(32)))
    bodies=[(node('v',l='x',_native_node=1),node('v',l='x',_native_node=2)),
            (node('i',v=1),node('i',v=1.0,extra=True)),
            (node('x',v={'/':{'bytes':'AQ'}}),node('x',v={'/':{'bytes':'AR=='}})),
            (node('#',l={'/':reference}),node('#',l={'/':'b'+reference[1:].upper()}))]
    for left,right in bodies:
        function=node('b',l='equal')
        for body in (left,right):function=node('a',f=function,a=node('f',l='x',b=body))
        yield 'closure-normalization',function
    values=[None,True,False,0,1.0,1.5,'',[],{},'a',{'/':'bad'},{'/':{'bytes':'!'}}]
    for index in range(count):
        choice=rng.randrange(5)
        if choice==0:
            original=copy.deepcopy(rng.choice(originals));key=rng.choice(['0','f','a','v','t','b','l','p','r','i']);original[key]=copy.deepcopy(rng.choice(values));yield 'random-field',original
        elif choice==1:
            encoded=''.join(rng.choices('ABab09+/=_-! \n\t\r',k=rng.randrange(30)));yield 'random-base64',node('x',v={'/':{'bytes':encoded}})
        elif choice==2:
            raw=varint(rng.choice([0,1,2,4]))+varint(rng.randrange(512))+varint(rng.choice([0,18,19]))+varint(rng.randrange(5))+rng.randbytes(rng.randrange(5))
            yield 'random-cid',node('#',l={'/':cid(raw)})
        elif choice==3:
            program=generated_program(rng,depth=2)
            if isinstance(program,dict):program[rng.choice(['0','f','a','b','v','t'])]=copy.deepcopy(rng.choice(values))
            yield 'nested-mutation',program
        else:
            program=node('@',p=rng.choice(['','standard',None,1]),r=rng.choice(values))
            if rng.randrange(2):program['l']=rng.choice([None,{}, {'/':cid(varint(1)+varint(297)+varint(18)+varint(0))},{'/':'bad'}])
            yield 'random-release',program


def main():
    args=argparse.ArgumentParser(description=__doc__)
    args.add_argument('--binary',type=Path,default=PACKAGE/'work/evaluation-validation')
    args.add_argument('--bun',default=os.environ.get('BUN') or shutil.which('bun') or '/workspace/tooling/bin/bun')
    args.add_argument('--seed',type=int,default=20261028)
    args.add_argument('--cases',type=int,default=2000)
    args.add_argument('--report',type=Path,default=PACKAGE/'reports/malformed-ir.json')
    options=args.parse_args()
    actual=subprocess.check_output(['git','rev-parse','HEAD'],cwd=ORACLE,text=True).strip()
    if actual!=ORACLE_SHA:raise SystemExit('oracle revision mismatch')
    if subprocess.run(['git','diff','--quiet','HEAD','--'],cwd=ORACLE).returncode:raise SystemExit('oracle tracked source is dirty')
    native=Peer([str(options.binary.resolve())]);oracle=Peer([options.bun,str(PACKAGE/'tests/oracle.mjs')])
    report={'seed':options.seed,'oracle':ORACLE_SHA,'binary_sha256':hashlib.sha256(options.binary.read_bytes()).hexdigest(),'checked':0,'failed':0,'categories':{},'failures':[],'oracle_crashes':[],'native_rejections_of_oracle_crashes':0}
    started=time.monotonic()
    try:
        for category,program in cases(random.Random(options.seed),options.cases):
            request={'op':'eval','program':program};expected=oracle.request(request);got=native.request(request)
            report['checked']+=1;report['categories'][category]=report['categories'].get(category,0)+1
            if 'adapter_error' in expected:
                # This is a bug observed in the actual oracle decoder, not a
                # successful decode or an evaluation result. Retain the exact
                # reproducers separately; require the native boundary to reject.
                report['oracle_crashes'].append({'category':category,'request':request,'error':expected['adapter_error'],'native':got})
                if got=={'decode_error':True}:
                    report['native_rejections_of_oracle_crashes']+=1
                    continue
            if not same(expected,got):
                report['failed']+=1
                failure={'category':category,'request':request,'expected':expected,'got':got,'difference':first_difference(expected,got)}
                if len(report['failures'])<30:report['failures'].append(failure)
                if report['failed']<=5:print(json.dumps(failure,ensure_ascii=False),flush=True)
        report['comparable']=report['checked']-len(report['oracle_crashes'])
        report['oracle_crash_count']=len(report['oracle_crashes'])
        report['passed']=report['failed']==0
        report['limitation']='Oracle decoder crashes are recorded separately; native rejects those malformed trees safely rather than reproducing host stack overflows.'
    finally:
        native.close();oracle.close();report['seconds']=round(time.monotonic()-started,3)
        options.report.parent.mkdir(parents=True,exist_ok=True);options.report.write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
    print(json.dumps({k:v for k,v in report.items() if k not in ('failures','oracle_crashes')}))
    return 0 if report.get('passed') else 1
if __name__=='__main__':raise SystemExit(main())
