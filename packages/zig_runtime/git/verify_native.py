#!/usr/bin/env python3
"""Independent Git correctness checks and seeded object/history generation.
Only this verifier invokes Git. Fixtures are isolated under repository work/.
"""
import argparse, base64, hashlib, importlib.util, json, os, random, subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]

def git(repo, *args, data=None, env=None):
    return subprocess.check_output(['git', '-C', str(repo), *args], input=data, env=env)

class Native:
    def __init__(self, binary, protocol=False):
        self.process = subprocess.Popen([str(binary)] + (['--protocol'] if protocol else []), stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True)
    def call(self, repo, action, **kw):
        self.process.stdin.write(json.dumps(dict(op='git',repo=str(repo),action=action,**kw))+'\n'); self.process.stdin.flush()
        line = self.process.stdout.readline()
        assert line, f'native process exited: {self.process.poll()}'
        result = json.loads(line)
        self.last_duration_ns = result.get('duration_ns') if isinstance(result, dict) else None
        if isinstance(result, dict):
            if 'result' in result: return result['result']
            assert 'error' not in result, result
        return result
    def close(self):
        self.process.stdin.close(); assert self.process.wait(timeout=10) == 0

def commit_data(repo, oid):
    raw = git(repo, 'cat-file', 'commit', oid).decode()
    headers, message = raw.split('\n\n',1); fields={}; parents=[]
    for line in headers.splitlines():
        if line.startswith('parent '): parents.append(line[7:])
        elif line.startswith(('tree ','author ','committer ')):
            k,v=line.split(' ',1); fields[k]=v
    return dict(id=oid,tree=fields['tree'],parents=parents,author=fields['author'],committer=fields['committer'],subject=message.split('\n',1)[0],message=message,timestamp=int(fields['committer'].rsplit(' ',2)[1]))

def main():
    ap=argparse.ArgumentParser(); ap.add_argument('--binary',default=str(ROOT/'work/git-native')); ap.add_argument('--protocol',action='store_true'); ap.add_argument('--seed',type=int,default=1847); ap.add_argument('--objects',type=int,default=100); args=ap.parse_args()
    rng=random.Random(args.seed); out=ROOT/'work/git-native-verification'; out.mkdir(parents=True,exist_ok=True)
    # A valid handcrafted pack guarantees both REF_DELTA and OFS_DELTA even if
    # this Git version chooses a different compression strategy for random data.
    spec=importlib.util.spec_from_file_location('real_world_verifier',ROOT/'work/oracle-real-world/dark/git/verify.py'); old=importlib.util.module_from_spec(spec); spec.loader.exec_module(old)
    fixture=out/'formats'; samples,idx=old.fixture(fixture)
    subprocess.run(['git','verify-pack',str(idx)],check=True,stdout=subprocess.DEVNULL)
    n=Native(args.binary,args.protocol); checks=0
    try:
        for kind,data,oid in samples:
            value=n.call(fixture,'object',id=oid)
            assert value['kind']==kind
            assert base64.b64decode(value['bytes'])==data==git(fixture,'cat-file',kind,oid)
            checks+=1
        assert n.call(fixture,'show',path='hello.txt')['text']=='hello'; checks+=1
        assert n.call(fixture,'head')['id']==samples[-2][2]; checks+=1
        assert n.call(fixture,'history',limit=20)==[commit_data(fixture,samples[-2][2])]; checks+=1
        # Deep REF_DELTA chains count delta links, not both the lookup wrapper
        # and decoder calls. Forty links is valid and below our depth budget.
        chain_repo=out/'ref-chain'; chain_git=chain_repo/'.git'; (chain_git/'objects/pack').mkdir(parents=True,exist_ok=True)
        chain_pack=b'PACK'+old.u32(2)+old.u32(41); chain_entries=[]; previous=b'hello'; previous_id=old.oid('blob',previous)
        for i in range(41):
            offset=len(chain_pack)
            if i==0: entry=old.header(3,len(previous))+__import__('zlib').compress(previous)
            else:
                data=previous+bytes([65+i%26]); delta=old.varint(len(previous))+old.varint(len(data))+bytes([0x90,len(previous),1,data[-1]])
                entry=old.header(7,len(delta))+previous_id+__import__('zlib').compress(delta)
                previous=data;previous_id=old.oid('blob',data)
            chain_entries.append((previous_id,offset,__import__('zlib').crc32(entry)));chain_pack+=entry
        pack_hash=old.sha(chain_pack);chain_pack+=pack_hash;ordered=sorted(chain_entries)
        chain_index=b'\xfftOc'+old.u32(2)+b''.join(old.u32(sum(e[0][0]<=i for e in chain_entries)) for i in range(256))
        chain_index+=b''.join(e[0] for e in ordered)+b''.join(old.u32(e[2]) for e in ordered)+b''.join(old.u32(e[1]) for e in ordered)+pack_hash;chain_index+=old.sha(chain_index)
        basename='pack-'+pack_hash.hex();(chain_git/'objects/pack'/f'{basename}.pack').write_bytes(chain_pack);(chain_git/'objects/pack'/f'{basename}.idx').write_bytes(chain_index);(chain_git/'HEAD').write_text(previous_id.hex()+'\n')
        subprocess.run(['git','verify-pack',str(chain_git/'objects/pack'/f'{basename}.idx')],check=True,stdout=subprocess.DEVNULL)
        assert base64.b64decode(n.call(chain_repo,'object',id=previous_id.hex())['bytes'])==previous;checks+=1

        def expect_error(repo, action, **kw):
            n.process.stdin.write(json.dumps(dict(op='git',repo=str(repo),action=action,**kw))+'\n'); n.process.stdin.flush()
            answer=json.loads(n.process.stdout.readline()); assert 'error' in answer,answer
        # A truncated pack must return an error, including Debug builds where
        # unchecked `size - 20` arithmetic would otherwise panic.
        pack=idx.with_suffix('.pack'); packed_bytes=pack.read_bytes()
        try:
            pack.write_bytes(packed_bytes[:12]);expect_error(fixture,'object',id=samples[0][2]);checks+=1
        finally:pack.write_bytes(packed_bytes)
        index_bytes=idx.read_bytes()
        try:
            idx.write_bytes(index_bytes[:-1]+bytes([index_bytes[-1]^1]));expect_error(fixture,'object',id=samples[0][2]);checks+=1
        finally:idx.write_bytes(index_bytes)

        # Every generated object is checked loose and then again after repacking.
        repo=out/f'generated-{args.seed}'; repo.mkdir(exist_ok=True)
        if (repo/'.git').exists():
            import shutil; shutil.rmtree(repo/'.git')
        git(repo,'init','-q','-b','main'); git(repo,'config','user.name','Native EYG oracle'); git(repo,'config','user.email','oracle@example.test')
        ids=[]
        for i in range(args.objects):
            alphabet=b'abcdefghijklmnopqrstuvwxyz\n\x00\xff'
            data=bytes(rng.choice(alphabet) for _ in range(rng.randrange(0,12000)))
            oid=git(repo,'hash-object','-w','--stdin',data=data).decode().strip(); ids.append(('blob',data,oid))
            value=n.call(repo,'object',id=oid); assert base64.b64decode(value['bytes'])==data; checks+=1
        for i in range(40):
            (repo/'changed.txt').write_text(f'{i//3}\n')
            (repo/'periodic.txt').write_text(f'{i//7}\n')
            person='Ada' if i%2 else 'Grace'
            env=os.environ | {'GIT_AUTHOR_NAME':person,'GIT_AUTHOR_DATE':f'{1700000000+i*60} +0000','GIT_COMMITTER_DATE':f'{1700000000+i*60} +0000'}
            git(repo,'add','.'); git(repo,'commit','--allow-empty','-qm',f'change {i}: '+('parser' if i%3 else 'runtime'),env=env)
        # Preserve otherwise-unreachable generated objects during gc by adding tags.
        for i,(_,_,oid) in enumerate(ids): git(repo,'update-ref',f'refs/tags/blob-{i}',oid)
        git(repo,'repack','-adf','--depth=30','--window=30'); git(repo,'prune-packed')
        for kind,data,oid in ids:
            assert base64.b64decode(n.call(repo,'object',id=oid)['bytes'])==git(repo,'cat-file',kind,oid)==data; checks+=1
        expected=git(repo,'rev-list','--first-parent','HEAD').decode().splitlines()
        actual=n.call(repo,'history',limit=100)
        assert actual==[commit_data(repo,oid) for oid in expected]; checks+=len(expected)
        assert n.call(repo,'resolve',ref='HEAD~7')==expected[7]; checks+=1
        assert n.call(repo,'resolve',ref='HEAD^')==expected[1]; checks+=1
        for contains,author in [('parser','Ada'),('runtime','Grace'),('change 1',''),('','Ada')]:
            want=[commit_data(repo,oid) for oid in expected if contains in commit_data(repo,oid)['message'] and author in commit_data(repo,oid)['author']]
            assert n.call(repo,'query',contains=contains,author=author,limit=100)==want; checks+=1
        for path in ['changed.txt','periodic.txt','missing']:
            want=git(repo,'log','--first-parent','--format=%H','--',path).decode().splitlines()
            assert [c['id'] for c in n.call(repo,'query',path=path,limit=100)]==want; checks+=1
        for revision in ['HEAD','HEAD~5','HEAD~20']:
            shown=n.call(repo,'show',ref=revision,path='changed.txt')
            assert base64.b64decode(shown['bytes'])==git(repo,'show',revision+':changed.txt'); checks+=1
        # Detached linked worktrees and packed refs are observed through commondir.
        linked=out/f'linked-{args.seed}'
        if linked.exists():
            import shutil; shutil.rmtree(linked)
        git(repo,'worktree','add','--detach','-q',str(linked),'HEAD~3')
        assert n.call(linked,'head')['id']==expected[3]; checks+=1
        git(repo,'pack-refs','--all'); assert n.call(repo,'head')['id']==expected[0]; checks+=1
        # A ref must stay fresh across requests; immutable-object caching must not
        # turn HEAD into a stale value when another writer updates its target.
        git(repo,'update-ref','refs/heads/main',expected[2])
        assert n.call(repo,'head')['id']==expected[2]; checks+=1
        git(repo,'update-ref','refs/heads/main',expected[0])
        git(repo,'config','--add','remote.Origin.url','https://example.test/a#b')
        git(repo,'config','--add','remote.Origin.url','ssh://example.test/second')
        git(repo,'config','--add','remote.Origin.pushurl','ssh://example.test/push')
        git(repo,'config','--add','remote.Origin.fetch','+refs/heads/*:refs/remotes/Origin/*')
        git(repo,'config','--add','remote.Backup.url','https://example.test/backup')
        remotes=n.call(repo,'remotes')
        assert remotes==[dict(name='Origin',urls=['https://example.test/a#b','ssh://example.test/second'],push_urls=['ssh://example.test/push'],fetch=['+refs/heads/*:refs/remotes/Origin/*']),dict(name='Backup',urls=['https://example.test/backup'],push_urls=['https://example.test/backup'],fetch=[])];checks+=1

        result=dict(passed=True,checks=checks,seed=args.seed,generated_objects=args.objects,generated_commits=40,formats=['loose','packed','OFS_DELTA','REF_DELTA','pack-index-v2','packed-refs','worktree','first-parent','path-history','ref-freshness'],native_git_runtime_dependency=False)
        (out/'result.json').write_text(json.dumps(result,indent=2)+'\n'); print(json.dumps(result))
    finally: n.close()
if __name__=='__main__': main()
