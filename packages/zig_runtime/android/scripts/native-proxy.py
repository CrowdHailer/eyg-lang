#!/usr/bin/env python3
"""JSONL transport for the real Zig session ABI; no interpreter is simulated."""
import argparse
import ctypes
import json
import sys


class NativeRuntime:
    def __init__(self, library):
        self.lib = ctypes.CDLL(library)
        self.lib.eyg_android_create.restype = ctypes.c_void_p
        self.lib.eyg_android_destroy.argtypes = [ctypes.c_void_p]
        self.lib.eyg_android_destroy.restype = None
        self.lib.eyg_android_result_len.argtypes = [ctypes.c_void_p]
        self.lib.eyg_android_result_len.restype = ctypes.c_size_t
        for name in ["evaluate", "resume"]:
            call = getattr(self.lib, "eyg_android_" + name)
            call.argtypes = [ctypes.c_void_p, ctypes.c_char_p, ctypes.c_size_t]
            call.restype = ctypes.c_void_p
        self.sessions = {}
        self.created = 0
        self.destroyed = 0

    def create(self):
        pointer = self.lib.eyg_android_create()
        if not pointer:
            raise MemoryError("Native session allocation failed")
        self.created += 1
        self.sessions[self.created] = pointer
        return self.created

    def invoke(self, method, session, text):
        pointer = self.sessions[session]
        raw = text.encode("utf-8")
        result = getattr(self.lib, "eyg_android_" + method)(pointer, raw, len(raw))
        if not result:
            raise RuntimeError("Native call returned a null buffer")
        length = self.lib.eyg_android_result_len(pointer)
        return ctypes.string_at(result, length).decode("utf-8")

    def destroy(self, session):
        pointer = self.sessions.pop(session, None)
        if pointer is not None:
            self.lib.eyg_android_destroy(pointer)
            self.destroyed += 1

    def request(self, method, args):
        if method == "create":
            return self.create()
        if method in ["evaluate", "resume"]:
            return self.invoke(method, *args)
        if method == "destroy":
            return self.destroy(*args)
        if method == "stats":
            return {"created": self.created, "destroyed": self.destroyed,
                    "live": len(self.sessions)}
        raise ValueError("Unknown native proxy method")

    def close(self):
        for session in list(self.sessions):
            self.destroy(session)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("library")
    runtime = NativeRuntime(parser.parse_args().library)
    try:
        for line in sys.stdin:
            request = {}
            try:
                request = json.loads(line)
                value = runtime.request(request["method"], request.get("args", []))
                response = {"id": request["id"], "ok": True, "value": value}
            except Exception as error:
                response = {"id": request.get("id"), "ok": False,
                            "error": f"{type(error).__name__}: {error}"}
            print(json.dumps(response, ensure_ascii=False), flush=True)
    finally:
        runtime.close()


if __name__ == "__main__":
    main()
