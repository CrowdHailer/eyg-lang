"""A real pseudoterminal driver; useful for parity tests and demo recordings.

Frame completion is the synchronized-output terminator emitted by both CLIs.
The VT model is pyte (test-only dependency), loaded from normal site-packages or
the workspace test dependency directory. Internal cell differential tests cover
attributes absent from pyte, notably dim, underline color, and hyperlinks.
"""
from __future__ import annotations

import codecs
import fcntl
import os
from pathlib import Path
import select
import signal
import struct
import subprocess
import sys
import termios
import time

REPO = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(REPO / "work/test-dependencies"))
try:
    import pyte
except ImportError as error:
    raise ImportError("Install the test dependency: python3 -m pip install pyte==0.8.2") from error

FRAME_END = b"\x1b[?2026l"


class Terminal:
    def __init__(self, command, cwd=REPO, width=80, height=24, env=None):
        self.width, self.height = width, height
        self.initial_width, self.initial_height = width, height
        self.master, self.slave = os.openpty()
        self.original_attrs = termios.tcgetattr(self.slave)
        fcntl.ioctl(self.slave, termios.TIOCSWINSZ, struct.pack("HHHH", height, width, 0, 0))
        self.screen = pyte.Screen(width, height)
        self.stream = pyte.ByteStream(self.screen)
        process_env = dict(os.environ, TERM="xterm-256color")
        process_env["PATH"] = "/workspace/tooling/bin:" + process_env.get("PATH", "")
        if env:
            process_env.update(env)
        self.process = subprocess.Popen(command, stdin=self.slave, stdout=self.slave, stderr=self.slave,
                                        cwd=cwd, env=process_env, start_new_session=True)
        os.set_blocking(self.master, False)
        self.recording = []
        self.started = time.monotonic()
        self.last_output = b""
        self._frame_pending = bytearray()
        self._output_decoder = codecs.getincrementaldecoder("utf-8")(errors="replace")
        self._input_decoder = codecs.getincrementaldecoder("utf-8")(errors="replace")

    def _read(self, timeout, decode=True):
        if not select.select([self.master], [], [], max(timeout, 0))[0]:
            return b""
        try:
            data = os.read(self.master, 1024 * 1024)
        except OSError:
            return b""
        if data:
            self.last_read_ns = time.perf_counter_ns()
            if decode:
                self.stream.feed(data)
            text = self._output_decoder.decode(data)
            if text:
                self.recording.append([time.monotonic() - self.started, "o", text])
        return data

    def frame(self, timeout=30):
        deadline = time.monotonic() + timeout
        output = self._frame_pending
        self._frame_pending = bytearray()
        while time.monotonic() < deadline:
            output.extend(self._read(min(.1, deadline - time.monotonic()), decode=False))
            if FRAME_END in output:
                # Timestamp receipt before running the observer's VT parser on
                # any chunk of this frame. Keep a following partial frame out
                # of the completed snapshot and carry it into the next read.
                self.frame_completed_ns = self.last_read_ns
                end = output.rfind(FRAME_END) + len(FRAME_END)
                completed = bytes(output[:end])
                self._frame_pending.extend(output[end:])
                self.stream.feed(completed)
                self.last_output = completed
                return completed
            if self.process.poll() is not None:
                raise RuntimeError(f"terminal exited {self.process.returncode}: {bytes(output)[-1000:]!r}")
        raise TimeoutError(f"no complete terminal frame in {timeout}s; output {bytes(output)[-1000:]!r}")

    def send(self, data, wait=True, timeout=30):
        if isinstance(data, str):
            data = data.encode()
        # A background task may have drawn while the other terminal was being
        # observed. Consume already available output before starting this key.
        self.settle(quiet=0)
        text = self._input_decoder.decode(data)
        if text:
            self.recording.append([time.monotonic() - self.started, "i", text])
        start = time.perf_counter_ns()
        os.write(self.master, data)
        output = self.frame(timeout) if wait else b""
        return output, (self.frame_completed_ns - start) if wait else time.perf_counter_ns() - start

    def settle(self, quiet=.1, timeout=5):
        """Drain asynchronous startup work before timing user interactions."""
        deadline = time.monotonic() + timeout
        output = self._frame_pending
        self._frame_pending = bytearray()
        if output:
            self.stream.feed(output)
        while time.monotonic() < deadline:
            data = self._read(min(quiet, deadline - time.monotonic()))
            if not data:
                self.last_output = bytes(output)
                return bytes(output)
            output.extend(data)
        raise TimeoutError("terminal did not become idle")

    def resize(self, width, height, timeout=30):
        self.settle(quiet=0)
        self.width, self.height = width, height
        self.screen.resize(height, width)
        self.recording.append([time.monotonic() - self.started, "r", f"{width}x{height}"])
        start = time.perf_counter_ns()
        fcntl.ioctl(self.slave, termios.TIOCSWINSZ, struct.pack("HHHH", height, width, 0, 0))
        os.killpg(self.process.pid, signal.SIGWINCH)
        output = self.frame(timeout)
        return output, self.frame_completed_ns - start

    def snapshot(self):
        return {"width": self.width, "height": self.height,
                "cells": [self.screen.buffer[y][x]._asdict() for y in range(self.height) for x in range(self.width)]}

    def plain(self):
        return "\n".join(self.screen.display)

    def quit(self, timeout=10):
        self.settle(quiet=0)
        self.recording.append([time.monotonic() - self.started, "i", "\x11"])
        os.write(self.master, b"\x11")
        deadline = time.monotonic() + timeout
        cleanup = bytearray()
        while self.process.poll() is None and time.monotonic() < deadline:
            cleanup.extend(self._read(.05))
        if self.process.poll() is None:
            raise TimeoutError("Ctrl+Q did not exit the terminal")
        while True:
            data = self._read(0)
            if not data:
                break
            cleanup.extend(data)
        return {"exit_code": self.process.returncode,
                "termios_restored": termios.tcgetattr(self.slave) == self.original_attrs,
                "paste_disabled": b"\x1b[?2004l" in cleanup,
                "cleanup": cleanup.decode(errors="replace")}

    def save_cast(self, path, title="EYG native shell"):
        import json
        path = Path(path)
        path.parent.mkdir(parents=True, exist_ok=True)
        header = {"version": 2, "width": self.initial_width, "height": self.initial_height, "timestamp": int(time.time()), "title": title,
                  "env": {"TERM": "xterm-256color", "SHELL": "eyg"}}
        path.write_text("\n".join(json.dumps(x, ensure_ascii=False) for x in [header, *self.recording]) + "\n")

    def close(self):
        if self.process.poll() is None:
            os.killpg(self.process.pid, signal.SIGTERM)
            try:
                self.process.wait(timeout=3)
            except subprocess.TimeoutExpired:
                os.killpg(self.process.pid, signal.SIGKILL)
                self.process.wait(timeout=3)
        os.close(self.master)
        os.close(self.slave)

    def __enter__(self):
        return self

    def __exit__(self, *exc):
        self.close()
