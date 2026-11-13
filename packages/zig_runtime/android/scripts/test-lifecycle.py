#!/usr/bin/env python3
"""Run the real pure-Kotlin ownership manager on a JDK, without Expo mocks."""
import argparse
import os
from pathlib import Path
import subprocess

APP = Path(__file__).resolve().parents[1]
PACKAGE = APP.parent
REPO = PACKAGE.parents[1]

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--jdk', type=Path, required=True)
    parser.add_argument('--gradle-cache', type=Path, default=Path(os.environ.get('GRADLE_USER_HOME', REPO / 'work/gradle-cache')))
    args = parser.parse_args()
    cache = args.gradle_cache / 'caches/modules-2/files-2.1'
    def artifact(group, name, version):
        files = list((cache / group / name / version).glob('*/*.jar'))
        if len(files) != 1:
            parser.error(f'Expected cached {group}:{name}:{version}; run the Android Gradle bootstrap first')
        return files[0]
    # These versions are cached by Expo 58's Gradle bootstrap. No network access.
    compiler = artifact('org.jetbrains.kotlin', 'kotlin-compiler-embeddable', '2.2.21')
    stdlib = artifact('org.jetbrains.kotlin', 'kotlin-stdlib', '2.2.21')
    jars = [compiler, stdlib,
            artifact('org.jetbrains.kotlin', 'kotlin-reflect', '2.2.10'),
            artifact('org.jetbrains.kotlinx', 'kotlinx-coroutines-core-jvm', '1.8.1'),
            artifact('org.jetbrains', 'annotations', '13.0')]
    out = APP / 'work/lifecycle-classes'
    out.mkdir(parents=True, exist_ok=True)
    source = APP / 'modules/eyg-runtime/android/src/main/java/expo/modules/eyg'
    subprocess.run([str(args.jdk / 'bin/java'), '-cp', os.pathsep.join(map(str, jars)),
                    'org.jetbrains.kotlin.cli.jvm.K2JVMCompiler', '-no-stdlib', '-no-reflect',
                    '-jvm-target', '17', '-classpath', str(stdlib), '-d', str(out),
                    str(source / 'NativeSessions.kt'), str(source / 'EygNative.kt'),
                    str(APP / 'tests/native/NativeSessionsTest.kt')], check=True)
    declarations = subprocess.check_output([str(args.jdk / 'bin/javap'), '-classpath', str(out), 'expo.modules.eyg.EygNative'], text=True)
    for expected in ['native long create()', 'native byte[] evaluate(long, byte[])', 'native byte[] resume(long, byte[])', 'native void cancel(long)', 'native void destroy(long)']:
        if expected not in declarations:
            raise RuntimeError(f'JNI declaration changed: {expected}')
    subprocess.run([str(args.jdk / 'bin/java'), '-cp', os.pathsep.join(map(str, [out, stdlib])),
                    'expo.modules.eyg.NativeSessionsTestKt'], check=True)

if __name__ == '__main__':
    main()
