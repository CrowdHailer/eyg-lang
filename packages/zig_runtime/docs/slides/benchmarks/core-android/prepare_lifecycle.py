from pathlib import Path
import re,subprocess,os,json,argparse
def find_package_root():
    for ancestor in Path(__file__).resolve().parents:
        if (ancestor / 'src/interpreter.zig').is_file() and (ancestor / 'build.zig').is_file():
            return ancestor
    raise SystemExit('Cannot locate Zig runtime package. Pass --package-root explicitly.')

parser=argparse.ArgumentParser()
parser.add_argument('--package-root',type=Path,default=None)
parser.add_argument('--work-dir',type=Path)
parser.add_argument('--jdk',type=Path)
parser.add_argument('--prepare-only',action='store_true',help='Generate host fixture sources without compiling or timing')
parser.add_argument('--gradle-cache',type=Path)
args=parser.parse_args()
if args.work_dir is not None: args.work_dir=args.work_dir.resolve()
root=(args.package_root or find_package_root()).resolve();out=(args.work_dir or root/'work/slides/android')/'lifecycle';out.mkdir(parents=True,exist_ok=True)
source=(root/'android/modules/eyg-runtime/android/src/main/java/expo/modules/eyg/NativeSessions.kt').read_text()
(out/'NativeSessions.kt').write_text(source)
without_interface=re.sub(r'internal interface NativeBackend \{.*?\n\}\n','',source,flags=re.S)
join=without_interface.replace('internal class NativeSessions(', 'internal class NativeSessionsJoin(').replace('override fun close() {','''override fun close() {
    // Controlled ablation: join every active evaluation before retiring IDs.
    val pending = synchronized(ownership) { sessions.values.toList() }
    pending.forEach { synchronized(it.serial) {} }
''')
(out/'NativeSessionsJoin.kt').write_text(join)
sync=without_interface.replace('internal class NativeSessions(', 'internal class NativeSessionsSyncFree(').replace('disposer.execute { idle.forEach { native.destroy(it.pointer) } }','idle.forEach { native.destroy(it.pointer) }')
(out/'NativeSessionsSyncFree.kt').write_text(sync)
probe=r'''package expo.modules.eyg
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicInteger

private class Backend(private val destructionMs: Long) : NativeBackend {
 val entered=CountDownLatch(1)
 val gate=CountDownLatch(1)
 val destroyed=CountDownLatch(1)
 override fun create(): Long = 1
 override fun evaluate(session:Long, request:ByteArray):ByteArray { entered.countDown();check(gate.await(5,TimeUnit.SECONDS)); return "42".toByteArray() }
 override fun resume(session:Long, request:ByteArray):ByteArray = evaluate(session,request)
 override fun cancel(session:Long) {}
 override fun destroy(session:Long) { if(destructionMs>0) Thread.sleep(destructionMs); destroyed.countDown() }
}
private data class Api(val create:()->Int,val call:(Int)->String,val close:()->Unit)
private fun factory(name:String,b:Backend):Api = when(name) {
 "optimized" -> NativeSessions(b).let {m->Api({m.create()},{m.call(it,"42",false)},{m.close()})}
 "join-active" -> NativeSessionsJoin(b).let {m->Api({m.create()},{m.call(it,"42",false)},{m.close()})}
 "sync-idle-free" -> NativeSessionsSyncFree(b).let {m->Api({m.create()},{m.call(it,"42",false)},{m.close()})}
 else -> error(name)
}
fun main(args:Array<String>) {
 val name=args[0];val workload=args[1];val iterations=args[2].toInt()
 val timer=Executors.newSingleThreadScheduledExecutor()
 val samples=mutableListOf<Long>()
 try {
  repeat(iterations+5) {i->
   val b=Backend(if(workload=="idle")25 else 0)
   val api=factory(name,b);val id=api.create()
   var worker:Thread?=null
   if(workload=="active") {
    worker=Thread {check(api.call(id)=="42")};worker.start()
    check(b.entered.await(5,TimeUnit.SECONDS))
    timer.schedule({b.gate.countDown()},25,TimeUnit.MILLISECONDS)
   }
   val start=System.nanoTime();api.close();val elapsed=System.nanoTime()-start
   if(i>=5)samples.add(elapsed)
   worker?.join(5000);check(worker?.isAlive!=true)
   check(b.destroyed.await(5,TimeUnit.SECONDS))
  }
 } finally {timer.shutdownNow()}
 println("{\"variant\":\"$name\",\"workload\":\"$workload\",\"samples_ns\":[${samples.joinToString(",")}],\"verified\":true}")
}
'''
(out/'Probe.kt').write_text(probe)
if args.prepare_only:
 print(json.dumps({'package_root':str(root),'generated_sources':str(out),'compiled':False,'timed':False}))
 raise SystemExit(0)
if args.jdk is None: parser.error('--jdk is required unless --prepare-only is used')
cache=(args.gradle_cache or root.parents[1]/'work/gradle-cache')/'caches/modules-2/files-2.1'
def artifact(group,name,version):
 files=list((cache/group/name/version).glob('*/*.jar'));assert len(files)==1;return files[0]
stdlib=artifact('org.jetbrains.kotlin','kotlin-stdlib','2.2.21')
jars=[artifact('org.jetbrains.kotlin','kotlin-compiler-embeddable','2.2.21'),stdlib,artifact('org.jetbrains.kotlin','kotlin-reflect','2.2.10'),artifact('org.jetbrains.kotlinx','kotlinx-coroutines-core-jvm','1.8.1'),artifact('org.jetbrains','annotations','13.0')]
(out/'classes').mkdir(exist_ok=True)
command=[str(args.jdk/'bin/java'),'-cp',os.pathsep.join(map(str,jars)),'org.jetbrains.kotlin.cli.jvm.K2JVMCompiler','-no-stdlib','-no-reflect','-jvm-target','17','-classpath',str(stdlib),'-d',str(out/'classes'),*[str(out/f)for f in ['NativeSessions.kt','NativeSessionsJoin.kt','NativeSessionsSyncFree.kt','Probe.kt']]]
r=subprocess.run(command,text=True,capture_output=True);(out/'build.log').write_text(r.stdout+r.stderr);print('exit',r.returncode,r.stderr[-2000:])
(out/'run.json').write_text(json.dumps([str(args.jdk/'bin/java'),'-cp',os.pathsep.join(map(str,[out/'classes',stdlib])),'expo.modules.eyg.ProbeKt']))
