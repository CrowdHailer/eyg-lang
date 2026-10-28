#!/usr/bin/env python3
"""Compile and run the real JNI shim on a Linux JDK without Android mocks."""
import argparse
import os
from pathlib import Path
import subprocess

APP = Path(__file__).resolve().parents[1]
def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--jdk', type=Path, required=True)
    parser.add_argument('--zig', required=True)
    args = parser.parse_args()
    work = APP / 'work'
    classes = work / 'jni-host'
    classes.mkdir(parents=True, exist_ok=True)
    def run(command): subprocess.run(list(map(str, command)), check=True)
    run([args.zig, 'build-lib', APP.parent / 'src/android_bridge.zig', '-dynamic', '-lc', '-O', 'ReleaseFast', '--name', 'eyg_android_host', '-femit-bin=' + str(work / 'libeyg_android_host.so')])
    run(['cc', '-shared', '-fPIC', '-O3', '-I' + str(args.jdk / 'include'), '-I' + str(args.jdk / 'include/linux'), APP / 'modules/eyg-runtime/android/src/main/cpp/eyg_jni.c', '-L' + str(work), '-leyg_android_host', '-Wl,-rpath,$ORIGIN', '-o', work / 'libeyg_jni_host.so'])
    run([args.jdk / 'bin/javac', '-d', classes, APP / 'tests/native/EygNative.java'])
    run([args.jdk / 'bin/java', '-cp', classes, 'expo.modules.eyg.EygNative', work / 'libeyg_jni_host.so'])

if __name__ == '__main__': main()
