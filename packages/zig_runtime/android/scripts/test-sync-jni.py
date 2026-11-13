#!/usr/bin/env python3
"""Exercise the real synchronous JNI entrypoint using a compiled Zig library."""
import argparse
from pathlib import Path
import subprocess
APP = Path(__file__).resolve().parents[1]
p = argparse.ArgumentParser(description=__doc__)
p.add_argument('library', type=Path)
p.add_argument('--jdk', type=Path, required=True)
p.add_argument('--jni-source', type=Path, default=APP/'modules/eyg-runtime/android/src/main/cpp/eyg_jni.c')
a = p.parse_args()
library = a.library.resolve()
work = APP/'work/sync-jni';work.mkdir(parents=True,exist_ok=True)
def run(cmd):subprocess.run(list(map(str,cmd)),check=True)
shim=work/'libeyg_sync_jni.so'
run(['cc','-shared','-fPIC','-O3','-I'+str(a.jdk/'include'),'-I'+str(a.jdk/'include/linux'),a.jni_source,library,'-Wl,-rpath,'+str(library.parent),'-o',shim])
run([a.jdk/'bin/javac','-d',work,APP/'tests/native/PureNative.java'])
run([a.jdk/'bin/java','-cp',work,'expo.modules.eyg.EygNative',shim])
