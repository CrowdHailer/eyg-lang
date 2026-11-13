#!/usr/bin/env python3
"""Compile Zig + JNI for the Android NDK; never download during a build."""
import argparse
import os
from pathlib import Path
import shutil
import subprocess
import sys

APP = Path(__file__).resolve().parents[1]
RUNTIME = APP.parent

def run(args):
    print(' '.join(map(str, args)), flush=True)
    subprocess.run(list(map(str, args)), check=True)

def main():
    p = argparse.ArgumentParser()
    p.add_argument('--ndk', type=Path, default=os.environ.get('ANDROID_NDK_HOME'))
    p.add_argument('--zig', default=os.environ.get('ZIG', shutil.which('zig')))
    p.add_argument('--abi', action='append', choices=['arm64-v8a', 'x86_64'])
    args = p.parse_args()
    if not args.ndk or not args.zig:
        p.error('Set ANDROID_NDK_HOME and ZIG (Zig 0.14.1), or pass --ndk and --zig')
    ndk = args.ndk.resolve()
    llvm = next((ndk / 'toolchains/llvm/prebuilt').glob('*'))
    api = 26
    work = APP / 'work/native'
    work.mkdir(parents=True, exist_ok=True)
    jni = APP / 'modules/eyg-runtime/android/src/main'
    for abi in args.abi or ['arm64-v8a', 'x86_64']:
        arch, triple = {'arm64-v8a': ('aarch64', 'aarch64-linux-android'), 'x86_64': ('x86_64', 'x86_64-linux-android')}[abi]
        out = jni / 'jniLibs' / abi
        out.mkdir(parents=True, exist_ok=True)
        libc = work / (abi + '.conf')
        libc.write_text('\n'.join([
            f'include_dir={llvm}/sysroot/usr/include',
            f'sys_include_dir={llvm}/sysroot/usr/include/{triple}',
            f'crt_dir={llvm}/sysroot/usr/lib/{triple}/{api}',
            'msvc_lib_dir=', 'kernel32_lib_dir=', 'gcc_dir=',
        ]) + '\n')
        run([args.zig, 'build-lib', RUNTIME / 'src/android_bridge.zig', '-dynamic', '-lc',
             '-target', f'{arch}-linux-android', '--libc', libc, '-O', 'ReleaseFast',
             '-fPIC', '-fstrip', '-z', 'max-page-size=16384', '-femit-bin=' + str(out / 'libeyg_zig.so'), '--name', 'eyg_zig'])
        run([llvm / 'bin' / f'{triple}{api}-clang', '-shared', '-fPIC', '-O3',
             jni / 'cpp/eyg_jni.c', '-L' + str(out), '-leyg_zig',
             '-Wl,-z,max-page-size=16384', '-Wl,-rpath,$ORIGIN', '-o', out / 'libeyg_jni.so'])

if __name__ == '__main__':
    main()
