#!/usr/bin/env python3
from pathlib import Path
import argparse,hashlib,json,re,subprocess,sys
cli=argparse.ArgumentParser();cli.add_argument('--package',type=Path);cli.add_argument('--output',type=Path);args=cli.parse_args()
root=args.package.resolve() if args.package else next(p for p in Path(__file__).resolve().parents if (p/'build.zig').exists() and (p/'src/main.zig').exists());out=args.output.resolve() if args.output else Path(__file__).resolve().parent
sys.path.insert(0,str(root.parent.parent/'work/test-dependencies'))
import pyte

def trace(s):
 style={k:False for k in ['bold','dim','italic','underline','blink','reverse','strike']};style.update(fg=None,bg=None,underline_color=None)
 original=style.copy();items=[];last=0
 for m in re.finditer(r'\x1b\[([0-9;:?]*)([A-Za-z])',s):
  for c in s[last:m.start()]:items.append(('char',c,tuple(style.items())))
  arg,cmd=m.groups();last=m.end()
  if cmd!='m':
   if cmd in ['H','J']:items.append((cmd,arg))
   continue
  if arg.startswith('58:'):
   parts=arg.split(':');style['underline_color']=tuple(parts[1:]);continue
  n=[int(p) if p else 0 for p in arg.split(';')];i=0
  while i<len(n):
   v=n[i];i+=1
   if v==0:style=original.copy()
   elif v in [1,2,3,4,5,7,9]:style[{1:'bold',2:'dim',3:'italic',4:'underline',5:'blink',7:'reverse',9:'strike'}[v]]=True
   elif 30<=v<=37:style['fg']=('index',v-30)
   elif 90<=v<=97:style['fg']=('index',v-90+8)
   elif 40<=v<=47:style['bg']=('index',v-40)
   elif 100<=v<=107:style['bg']=('index',v-100+8)
   elif v in [38,48]:
    dest='fg' if v==38 else 'bg';kind=n[i];i+=1
    if kind==5:style[dest]=('index',n[i]);i+=1
    elif kind==2:style[dest]=('rgb',*n[i:i+3]);i+=3
    else:raise RuntimeError(('unsupported-color',v,kind))
   else:raise RuntimeError(('unsupported-SGR',v))
 for c in s[last:]:items.append(('char',c,tuple(style.items())))
 return items,style

def screen(s,w,h):
 q=pyte.Screen(w,h);stream=pyte.ByteStream(q);stream.feed(re.sub(r'\x1b\[58:[0-9:]*m','',s).encode());return [[q.buffer[y][x]._asdict() for x in range(w)] for y in range(h)]

def sha(b):return hashlib.sha256(b).hexdigest()
requests={
 'empty':[],
 'arithmetic':[{'paste':'!int_add(20, 22)'}],
 'unicode':[{'key':'s'},{'paste':'hello λé世界'},{'key':'enter'}],
 'picker':[{'key':'j'},{'key':'s'}],
 'nested':[{'paste':'let data = {count: 42, items: [1, 2, 3], name: "EYG"} let {count, items} = data !list_fold(items, count, (x, total) -> { !int_add(x, total) })'}],
 'history':[{'paste':'{answer: 42, label: "λ"}'},{'key':'enter'},{'key':'up'}]
}
p=subprocess.Popen([str(root/'zig-out/bin/eyg'),'--protocol'],stdin=subprocess.PIPE,stdout=subprocess.PIPE,cwd=root)
frames={}
try:
 for name,events in requests.items():
  p.stdin.write((json.dumps({'op':'tui','width':80,'height':24,'events':events})+'\n').encode());p.stdin.flush();frames[name]=json.loads(p.stdout.readline())['frames'][-1]
finally:p.stdin.close();p.wait(timeout=10)
# Explicit synthetic style coverage supplements real TUI frames.
styles=[{'fg':None,'bg':None,'modifiers':0,'underline_color':None},{'fg':[12,34,56],'bg':200,'modifiers':127,'underline_color':[89,123,210]},{'fg':14,'bg':[1,2,3],'modifiers':2,'underline_color':202}]
frames['synthetic-all-styles']={'width':12,'height':1,'cells':[{'symbol':chr(65+i),'width':1,'link':'','sub_modifiers':0,**styles[i//4]} for i in range(12)]}
checks=[]
for name,frame in frames.items():
 raw=subprocess.check_output([str(out/'ansi-qa')],input=json.dumps(frame).encode());pair=json.loads(raw)
 before,after=pair['before'],pair['after'];equal=trace(before)==trace(after) and screen(before,frame['width'],frame['height'])==screen(after,frame['width'],frame['height'])
 assert equal,name
 for condition in ['before','after']:(out/(name+'.'+condition+'.ansi')).write_bytes(pair[condition].encode())
 checks.append({'name':name,'synthetic':name.startswith('synthetic'),'cell_count':len(frame['cells']),'vt_cells_equal':True,'extended_effective_style_trace_equal':True,'before_bytes':len(before.encode()),'after_bytes':len(after.encode()),'before_sha256':sha(before.encode()),'after_sha256':sha(after.encode())})
report={'passed':True,'model':'pyte0.8.2 (unsupported underline-color SGR removed before that observer only) plus exact effective-SGR-per-character/cursor trace including dim,underline colors,all modifier bits','native_binary_sha256':sha((root/'zig-out/bin/eyg').read_bytes()),'qa_binary_sha256':sha((out/'ansi-qa').read_bytes()),'checks':checks}
(out/'ansi-parity.json').write_text(json.dumps(report,indent=2)+'\n');print(json.dumps(report,indent=2))
