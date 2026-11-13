#!/usr/bin/env python3
"""One-shot real C ABI transport used by synchronous callback host tests."""
import ctypes
import sys
lib = ctypes.CDLL(sys.argv[1])
lib.eyg_android_create.restype = ctypes.c_void_p
lib.eyg_android_pure.argtypes = [ctypes.c_void_p, ctypes.c_char_p, ctypes.c_size_t]
lib.eyg_android_pure.restype = ctypes.c_void_p
lib.eyg_android_result_len.argtypes = [ctypes.c_void_p]
lib.eyg_android_result_len.restype = ctypes.c_size_t
lib.eyg_android_destroy.argtypes = [ctypes.c_void_p]
session = lib.eyg_android_create()
if not session:
    raise MemoryError('Unable to allocate native session')
try:
    data = sys.stdin.buffer.read(65537)
    result = lib.eyg_android_pure(session, data, len(data))
    if not result:
        raise RuntimeError('Null native callback result')
    sys.stdout.buffer.write(ctypes.string_at(result, lib.eyg_android_result_len(session)))
finally:
    lib.eyg_android_destroy(session)
