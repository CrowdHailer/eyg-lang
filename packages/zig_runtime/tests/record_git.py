#!/usr/bin/env python3
"""Record real Zig TUI queries; export cast, snapshots, verification and MP4.
No terminal output is replayed during capture. Movie export renders the cast.
"""
from __future__ import annotations
import argparse,hashlib,json,math,subprocess,sys,time
from pathlib import Path
from terminal import Terminal,REPO

REV='f1e32bad77d7ffdef6c416cb7ccbf7b23ec0bbd9'

def record(binary,out):
 out.mkdir(parents=True,exist_ok=True);checks=[]
 with Terminal([str(binary)],cwd=REPO,width=136,height=40) as terminal:
  executable_sha256=hashlib.sha256(Path(f"/proc/{terminal.process.pid}/exe").read_bytes()).hexdigest()
  terminal.frame();time.sleep(.8);terminal.settle(quiet=.2)
  def command(title,code,expected):
   terminal.send('\x1b[200~'+code+'\x1b[201~');time.sleep(.7);terminal.settle(quiet=.15)
   previous_matches=terminal.plain().count(expected)
   started=time.perf_counter_ns()
   _,feedback=terminal.send('\r')
   deadline=time.monotonic()+30
   while terminal.plain().count(expected)<=previous_matches and time.monotonic()<deadline:
    terminal.frame(timeout=max(.1,deadline-time.monotonic()))
   duration=terminal.frame_completed_ns-started
   screen=terminal.plain()
   assert '✘' not in screen,screen
   assert screen.count(expected)>previous_matches,(title,expected,screen)
   row=dict(title=title,code=code,enter_to_first_feedback_ms=round(feedback/1e6,4),enter_to_complete_frame_ms=round(duration/1e6,4),verified_visible=expected)
   checks.append(row);(out/f'{len(checks):02d}-screen.txt').write_text(screen+'\n');time.sleep(1.6)
  command('Load the EYG Git facade',f'let git = import "packages/zig_runtime/git/native.eyg"\nlet repo = {json.dumps(str(REPO))}\nlet revision = "{REV}"\nlet subjects = (rows) -> {{ !list_fold(rows, [], (commit, found) -> {{ [commit.subject, ..found] }}) }}\n{{}}','= {}')
  command('Inspect the current commit', 'subjects(git.query({repo, ref: revision, limit: 1}))','Verify subsecond TUI history')
  command('Search commit messages', 'subjects(git.query({repo, ref: revision, contains: "TUI", limit: 1}))','Verify subsecond TUI history')
  command('Filter by author and time window', 'subjects(git.query({repo, ref: revision, author: "Peter", since: 1793200000, until: 1793210000, limit: 1}))','Verify subsecond TUI history')
  command('Find changes to the Git reader', 'subjects(git.query({repo, ref: revision, path: "dark/git/read.eyg", limit: 1}))','Accelerate EYG Git decoding')
  terminal.send('\x1b[A');time.sleep(.8);terminal.send('k');time.sleep(1.3)
  checks.append(dict(title='Browse and expand query history',verified_visible='selected history'))
  assert 'selected history' in terminal.plain(),terminal.plain()
  result=terminal.quit();assert result['exit_code']==0 and result['termios_restored'],result
  terminal.save_cast(out/'eyg-git-history.cast','EYG in Zig: structured queries over its own Git history')
 (out/'verification.json').write_text(json.dumps(dict(real_pty=True,executable_sha256=executable_sha256,oracle_git_revision=REV,steps=checks,cleanup=result),indent=2)+'\n')
 return out/'eyg-git-history.cast'

def movie(cast,out,fps=15):
 import pyte
 from PIL import Image,ImageDraw,ImageFont
 lines=[json.loads(line) for line in cast.read_text().splitlines()];header=lines[0];events=lines[1:]
 width,height=header['width'],header['height'];cellw,cellh=9,19;bar=38
 fontpath='/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf';font=ImageFont.truetype(fontpath,14);bold=ImageFont.truetype(fontpath.replace('.ttf','-Bold.ttf'),14)
 screen=pyte.Screen(width,height);stream=pyte.Stream(screen)
 colours={'default':'#d9e0ee','black':'#181b24','red':'#f38ba8','green':'#a6e3a1','brown':'#f9e2af','blue':'#89b4fa','magenta':'#cba6f7','cyan':'#94e2d5','white':'#cdd6f4','brightblack':'#6c7086','brightred':'#f38ba8','brightgreen':'#a6e3a1','brightbrown':'#f9e2af','brightblue':'#89b4fa','brightmagenta':'#cba6f7','brightcyan':'#94e2d5','brightwhite':'#ffffff'}
 def colour(value,default):
  if value=='default':return default
  return colours.get(value,'#'+value if len(value)==6 else default)
 def render():
  image=Image.new('RGB',(width*cellw,height*cellh+bar),'#181b24');draw=ImageDraw.Draw(image)
  draw.rectangle((0,0,image.width,bar),fill='#242938');draw.text((12,10),'EYG / Zig   ·   local Git history as structured data',font=bold,fill='#a6e3a1')
  for y in range(height):
   for x in range(width):
    char=screen.buffer[y][x];fg=colour(char.fg,'#d9e0ee');bg=colour(char.bg,'#181b24')
    if char.reverse:fg,bg=bg,fg
    px,py=x*cellw,y*cellh+bar
    if bg!='#181b24':draw.rectangle((px,py,px+cellw,py+cellh),fill=bg)
    if char.data and char.data!=' ':draw.text((px,py),char.data,font=bold if char.bold else font,fill=fg)
    if char.underscore:draw.line((px,py+cellh-2,px+cellw,py+cellh-2),fill=fg)
  return image
 duration=events[-1][0]+.8;index=0;frame=render();encoded=frame.tobytes()
 process=subprocess.Popen(['ffmpeg','-hide_banner','-loglevel','error','-y','-f','rawvideo','-pixel_format','rgb24','-video_size',f'{frame.width}x{frame.height}','-framerate',str(fps),'-i','-','-an','-c:v','libx264','-preset','fast','-crf','20','-pix_fmt','yuv420p','-movflags','+faststart',str(out/'eyg-git-history.mp4')],stdin=subprocess.PIPE)
 for n in range(math.ceil(duration*fps)):
  changed=False
  while index<len(events) and events[index][0]<=n/fps:
   _,kind,data=events[index]
   if kind=='o':stream.feed(data);changed=True
   index+=1
  if changed:frame=render();encoded=frame.tobytes()
  process.stdin.write(encoded)
  if n==math.ceil(duration*fps)-int(fps*1.5):frame.save(out/'eyg-git-history.png')
 process.stdin.close();assert process.wait()==0

def main():
 ap=argparse.ArgumentParser();ap.add_argument('--binary',type=Path,default=REPO/'packages/zig_runtime/zig-out/bin/eyg');ap.add_argument('--output',type=Path,default=REPO/'work/eyg-git-recording');ap.add_argument('--movie-only',action='store_true');ap.add_argument('--no-movie',action='store_true');args=ap.parse_args()
 cast=args.output/'eyg-git-history.cast' if args.movie_only else record(args.binary.resolve(),args.output)
 if not args.no_movie:movie(cast,args.output)
 print(args.output)
if __name__=='__main__':main()
