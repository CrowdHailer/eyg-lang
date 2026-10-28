#!/usr/bin/env python3
"""Native Git writes, checked against Git hashes/fsck and lock races."""
import argparse,base64,hashlib,json,shutil,subprocess
from pathlib import Path
from verify_native import ROOT,git,Native

def main():
 ap=argparse.ArgumentParser();ap.add_argument('--binary',default=str(ROOT/'work/git-native'));ap.add_argument('--protocol',action='store_true');args=ap.parse_args()
 repo=ROOT/'work/git-native-verification/writes';shutil.rmtree(repo,ignore_errors=True)
 native=Native(args.binary,args.protocol);checks=0
 def raw(action,**kw):
  native.process.stdin.write(json.dumps(dict(op='git',repo=str(repo),action=action,**kw))+'\n');native.process.stdin.flush();return json.loads(native.process.stdout.readline())
 def fails(action,reason=None,**kw):
  result=raw(action,**kw);assert 'error' in result,result
  if reason:assert reason in str(result),result
  return result
 person=dict(name='EYG writer',email='eyg@example.test',timestamp=1700000000,timezone='+0000')
 try:
  native.call(repo,'init',branch='main');checks+=1
  fails('init','RepositoryExists');checks+=1
  data=bytes(range(256))*5
  oid=native.call(repo,'write_blob',bytes=base64.b64encode(data).decode());expected=hashlib.sha1(f'blob {len(data)}\0'.encode()+data).hexdigest()
  assert oid==expected and git(repo,'cat-file','blob',oid)==data;checks+=1
  nested=native.call(repo,'write_tree',entries=[dict(name='leaf',mode='100755',id=oid)])
  tree=native.call(repo,'write_tree',entries=[dict(name='a',mode='40000',id=nested),dict(name='a.c',mode='100644',id=oid),dict(name='link',mode='120000',id=oid)])
  rawtree=git(repo,'cat-file','tree',tree)
  assert rawtree.index(b'a.c\0')<rawtree.index(b'a\0');checks+=1
  first=native.call(repo,'commit_tree',tree=tree,parents=[],author=person,committer=person,message='first commit')
  assert git(repo,'cat-file','commit',first).endswith(b'\n\nfirst commit\n');checks+=1
  native.call(repo,'update_ref',ref='refs/heads/main',expected=None,id=first);checks+=1
  fails('update_ref','StaleReference',ref='refs/heads/main',expected=None,id=first);checks+=1
  native.call(repo,'create_branch',name='other',id=first);checks+=1
  fails('create_branch','StaleReference',name='other',id=first);checks+=1
  second=native.call(repo,'commit_snapshot',ref='refs/heads/main',expected=first,files=[dict(path='src/deep/file.txt',text='hello EYG\n',mode='100644'),dict(path='run',text='#!/bin/sh\n',mode='100755')],author=person,committer=person,message='second commit')
  assert git(repo,'show','HEAD:src/deep/file.txt')==b'hello EYG\n';checks+=1
  assert git(repo,'rev-parse','HEAD^').decode().strip()==first;checks+=1
  fails('commit_snapshot','StaleReference',ref='refs/heads/main',expected=first,files=[],author=person,committer=person,message='stale');checks+=1
  fails('write_tree','DuplicatePath',entries=[dict(name='same',mode='100644',id=oid)]*2);checks+=1
  fails('snapshot_tree','InvalidPath',files=[dict(path='../escape',text='bad')]);checks+=1
  fails('snapshot_tree','InvalidPath',files=[dict(path='.git/config',text='bad')]);checks+=1
  fails('snapshot_tree','DuplicatePath',files=[dict(path='file',text='bad'),dict(path='file/sub',text='bad')]);checks+=1
  git(repo,'pack-refs','--all');native.call(repo,'update_ref',ref='refs/heads/main',expected=second['id'],id=first);checks+=1
  # A writer owns only locks it created; failures must preserve somebody else's.
  packedlock=repo/'.git/packed-refs.lock';packedlock.write_text('other writer')
  fails('update_ref',ref='refs/heads/main',expected=first,id=second['id']);assert packedlock.read_text()=='other writer';packedlock.unlink();checks+=1
  lock=repo/'.git/refs/heads/main.lock';lock.write_text('other writer')
  fails('update_ref',ref='refs/heads/main',expected=first,id=second['id']);assert lock.read_text()=='other writer';assert not packedlock.exists();lock.unlink();checks+=1
  request=json.dumps(dict(op='git',repo=str(repo),action='update_ref',ref='refs/heads/main',expected=first,id=second['id']))+'\n'
  cmd=[str(args.binary)]+(['--protocol'] if args.protocol else [])
  contenders=[subprocess.Popen(cmd,stdin=subprocess.PIPE,stdout=subprocess.PIPE,text=True) for _ in range(2)]
  for process in contenders:process.stdin.write(request);process.stdin.close()
  replies=[json.loads(process.stdout.readline()) for process in contenders]
  for process in contenders:assert process.wait(timeout=10)==0
  assert sum('error' not in reply for reply in replies)==1,replies
  assert git(repo,'rev-parse','HEAD').decode().strip()==second['id'];checks+=1
  subprocess.run(['git','-C',str(repo),'fsck','--strict'],stdout=subprocess.DEVNULL,check=True);checks+=1
  result=dict(passed=True,checks=checks,features=['SHA1 object names','zlib objects','canonical tree ordering','commit headers','nested complete snapshots','branch create','packed refs','stale-tip CAS','exclusive writer locks','concurrent CAS','git fsck --strict'],mutates_worktree=False)
  (repo.parent/'writes.json').write_text(json.dumps(result,indent=2)+'\n');print(json.dumps(result))
 finally:native.close()
if __name__=='__main__':main()
