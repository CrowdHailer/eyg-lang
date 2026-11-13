#!/usr/bin/env python3
"""Deterministic differential checks against the pinned next-tui implementation.

Run from any directory; build first. A mismatch is a failing test, never an
expected failure. Reproducers retain the seed, original request, and a smaller
request. No renderer output is normalized away.
"""
from __future__ import annotations

import argparse
import base64
from collections import Counter
import hashlib
import json
import os
from pathlib import Path
import random
import select
import shutil
import subprocess
import sys
import time

PACKAGE = Path(__file__).resolve().parents[1]
REPO = PACKAGE.parents[1]
ORACLE = Path(os.environ.get("EYG_ORACLE_ROOT", REPO / "work/oracle-next-tui")).resolve()
ORACLE_SHA = "be502aa03df926a8f9df474a0a7fe16c8fb14fbd"
UNICODE = ["", "abc", "a\nb\t\"", "λ", "é", "e\u0301", "👩‍💻", "\u2028", "Straße", "İ",
           "\r\n", "각", "🇬🇧🇳🇿", "👩🏽‍💻", "क्‍ष", "क्\u0937", "ΟΣ", "ΟΣΑ", "Σ'", "ß"]


class Peer:
    def __init__(self, command: list[str], timeout: float = 30):
        self.command, self.timeout = command, timeout
        self.process = subprocess.Popen(command, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                        stderr=subprocess.PIPE, bufsize=0, cwd=REPO)
        self.stderr_tail = bytearray()

    def request(self, payload):
        encoded = json.dumps(payload, ensure_ascii=True, separators=(",", ":")).encode() + b"\n"
        self.process.stdin.write(encoded)
        self.process.stdin.flush()
        # Use raw os.read rather than buffered readline: large frame responses
        # otherwise can hide bytes from select and cause a false timeout.
        deadline, response = time.monotonic() + self.timeout, bytearray()
        stderr_open = True
        while True:
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                raise TimeoutError(f"{self.command[0]} did not answer within {self.timeout}s")
            watched = [self.process.stdout] + ([self.process.stderr] if stderr_open else [])
            ready, _, _ = select.select(watched, [], [], remaining)
            if not ready:
                raise TimeoutError(f"{self.command[0]} did not answer within {self.timeout}s")
            if self.process.stderr in ready:
                chunk = os.read(self.process.stderr.fileno(), 65536)
                stderr_open = bool(chunk)
                self.stderr_tail.extend(chunk)
                del self.stderr_tail[:-65536]
            if self.process.stdout in ready:
                chunk = os.read(self.process.stdout.fileno(), 65536)
                if not chunk:
                    raise RuntimeError(f"{self.command[0]} exited {self.process.poll()}: "
                                       + self.stderr_tail.decode(errors="replace")[-2000:])
                response.extend(chunk)
                if response.endswith(b"\n"):
                    return json.loads(response)

    def close(self):
        if self.process.poll() is None:
            try:
                self.process.stdin.close()
                self.process.wait(timeout=.25)
            except (subprocess.TimeoutExpired, BrokenPipeError):
                self.process.terminate()
                try:
                    self.process.wait(timeout=1)
                except subprocess.TimeoutExpired:
                    self.process.kill()
                    self.process.wait(timeout=1)
        for stream in (self.process.stdin, self.process.stdout, self.process.stderr):
            if stream and not stream.closed:
                stream.close()

    def restart(self):
        self.close()
        self.__init__(self.command, self.timeout)


def node(tag, **fields):
    return {"0": tag, **fields}


def call(function, *arguments):
    for argument in arguments:
        function = node("a", f=function, a=argument)
    return function


def builtin(name, *arguments):
    return call(node("b", l=name), *arguments)


def returned_resumption_program():
    return call(node("h", l="Ping"),
                node("f", l="x", b=node("f", l="resume", b=node("v", l="resume"))),
                node("f", l="_", b=call(node("p", l="Ping"), node("i", v=1))))


def unicode_record_program():
    value = node("u")
    for label, number in (("\ue000", 1), ("𐀀", 2), ("😀", 3), ("λ", 4)):
        value = call(node("e", l=label), node("i", v=number), value)
    return value


def literal_fixture(rng, depth=2):
    """Produce the same arbitrary value as both canonical IR and fixture JSON."""
    kind = rng.choice(("int", "string", "binary", "list", "record", "tagged") if depth else ("int", "string", "binary"))
    if kind == "int":
        value = rng.randrange(-1000, 1000)
        return node("i", v=value), {"integer": value}
    if kind == "string":
        value = rng.choice(UNICODE)
        return node("s", v=value), {"string": value}
    if kind == "binary":
        data = bytes(rng.randrange(256) for _ in range(rng.randrange(16)))
        encoded = {"/": {"bytes": base64.b64encode(data).decode().rstrip("=")}}
        return node("x", v=encoded), {"binary": encoded}
    if kind == "tagged":
        label = rng.choice(("Some", "X", "Nested", "Ok"))
        inner, value = literal_fixture(rng, depth - 1)
        return call(node("t", l=label), inner), {"tagged": {"label": label, "value": value}}
    if kind == "list":
        result, values = node("ta"), []
        for _ in range(rng.randrange(5)):
            inner, value = literal_fixture(rng, depth - 1)
            result = call(node("c"), inner, result)
            values.insert(0, value)
        return result, {"list": values}
    result, values = node("u"), {}
    for key in rng.sample(("a", "z", "Aa", "BB", "value", "\ue000", "𐀀", "😀", "λ"), rng.randrange(5)):
        inner, value = literal_fixture(rng, depth - 1)
        result = call(node("e", l=key), inner, result)
        values[key] = value
    return result, {"record": values}


def generated_program(rng, depth=4, kind=None, scope=()):
    """A bounded, typed grammar plus intentional well-formed runtime errors.

    Random trees cover lexical binding, closure capture, records, unions, lists,
    strings, integer edges and handled effects, without relying on Zig parsing.
    The bounded grammar excludes diverging recursion. Recursion has spec cases.
    """
    kind = kind or rng.choice(("int", "string", "list", "record", "union", "error", "effect", "builtin", "match", "reference", "fix"))
    if depth <= 0:
        if kind == "int":
            return rng.choice([node("i", v=rng.randint(-1000, 1000)), node("v", l=rng.choice(scope))]) if scope else node("i", v=rng.choice([-9007199254740991, -1, 0, 1, 9007199254740991]))
        if kind == "string":
            return node("s", v=rng.choice(UNICODE))
        if kind == "list":
            return node("ta")
        if kind == "record":
            return node("u")
        if kind == "union":
            return call(node("t", l="Some"), node("u"))
        if kind == "error":
            return rng.choice([node("v", l="missing"), node("b", l="missing"), node("z")])
        return call(node("p", l="Probe"), node("i", v=1))
    descend = lambda k=kind: generated_program(rng, depth - 1, k, scope)
    if kind == "int":
        choice = rng.randrange(7)
        if choice == 0:
            return node("i", v=rng.randint(-10000, 10000))
        if choice == 1:
            label = f"x{depth}"
            return node("l", l=label, v=descend(), t=generated_program(rng, depth - 1, "int", scope + (label,)))
        if choice == 2:
            return call(node("f", l="n", b=builtin("int_add", node("v", l="n"), node("i", v=3))), descend())
        if choice == 3:
            return call(node("g", l="answer"), call(node("e", l="answer"), descend(), node("u")))
        if choice == 4:
            return builtin("int_absolute", descend())
        return builtin(rng.choice(("int_add", "int_subtract", "int_multiply")), descend(), descend())
    if kind == "string":
        if rng.randrange(3) == 0:
            return builtin(rng.choice(("string_uppercase", "string_lowercase")), descend())
        if rng.randrange(2) == 0:
            return builtin("string_append", descend(), descend())
        return builtin("int_to_string", descend("int"))
    if kind == "list":
        result = node("ta")
        for _ in range(rng.randrange(5)):
            result = call(node("c"), descend(rng.choice(("int", "string"))), result)
        return result
    if kind == "record":
        result = node("u")
        for key in rng.sample(("x", "y", "name", "a", "z"), rng.randrange(5)):
            result = call(node("e", l=key), descend(rng.choice(("int", "string", "list"))), result)
        return result
    if kind == "union":
        return builtin(rng.choice(("equal", "int_compare", "int_divide")), descend("int"), descend("int"))
    if kind == "effect":
        # A deep handler resumes once, with a transformed argument. Both the
        # handler function and suspended continuation are exercised.
        function = node("f", l="_", b=builtin("int_add", call(node("p", l="Probe"), node("i", v=rng.randrange(9))), node("i", v=2)))
        handler = node("f", l="x", b=node("f", l="resume", b=call(node("v", l="resume"), builtin("int_add", node("v", l="x"), node("i", v=1)))))
        return call(node("h", l="Probe"), handler, function)
    if kind == "builtin":
        name = rng.choice(("int_parse", "string_split", "string_split_once", "string_replace", "string_length",
                           "string_starts_with", "string_ends_with", "string_to_binary", "string_from_binary",
                           "binary_from_integers", "binary_concat", "binary_compare", "binary_size", "binary_fold", "list_fold", "list_pop"))
        string = lambda: node("s", v=rng.choice(UNICODE))
        binary = lambda: builtin("string_to_binary", string())
        if name == "int_parse":
            return builtin(name, node("s", v=rng.choice(["", "x", "42", "-0004", "+1", "12.0", "9007199254740992", " 12", "12 "])))
        if name in ("string_split", "string_split_once", "string_starts_with", "string_ends_with"):
            return builtin(name, string(), string())
        if name == "string_replace":
            return builtin(name, string(), string(), string())
        if name in ("string_length", "string_to_binary"):
            return builtin(name, string())
        if name in ("string_from_binary", "binary_size"):
            return builtin(name, binary())
        if name in ("binary_concat", "binary_compare"):
            return builtin(name, binary(), binary())
        if name in ("list_fold", "binary_fold"):
            collection = descend("list") if name == "list_fold" else binary()
            return builtin(name, collection, node("i", v=0), node("f", l="el", b=node("f", l="acc", b=builtin("int_add", node("v", l="el"), node("v", l="acc")))))
        if name == "list_pop":
            return builtin(name, descend("list"))
        collection = node("ta")
        for _ in range(rng.randrange(8)):
            collection = call(node("c"), node("i", v=rng.randrange(-300, 1000)), collection)
        return builtin(name, collection)
    if kind == "match":
        label = rng.choice(("Some", "Other"))
        tagged = call(node("t", l=label), descend("int"))
        branch = node("f", l="x", b=builtin("int_add", node("v", l="x"), node("i", v=1)))
        return call(node("m", l="Some"), branch, node("n"), tagged)
    if kind == "reference":
        return rng.choice([node(".", i="./module.eyg"), node("@", p="standard"), node("@", p="demo", r=rng.randrange(1, 20)),
                           node("#", l={"/": "baguqeera2rxu3p44bxjutnjlpeffcmkgdmh5mmyeqgpatyaae6ezybzg4azq"})])
    if kind == "fix":
        recurse = call(node("v", l="self"), builtin("int_subtract", node("v", l="n"), node("i", v=1)))
        branch = node("f", l="_", b=node("i", v=0))
        otherwise = node("f", l="_", b=builtin("int_add", node("v", l="n"), recurse))
        body = call(node("m", l="Eq"), branch, otherwise, builtin("int_compare", node("v", l="n"), node("i", v=0)))
        return call(builtin("fix", node("f", l="self", b=node("f", l="n", b=body))), node("i", v=rng.randrange(30)))
    choice = rng.randrange(5)
    if choice == 0:
        return call(node("i", v=7), descend("int"))
    if choice == 1:
        return builtin("int_add", descend("string"), descend("int"))
    if choice == 2:
        return call(node("g", l="absent"), descend("record"))
    if choice == 3:
        return builtin("int_add", node("i", v=9007199254740991), node("i", v=1))
    return descend("error")


def generated_source(rng, depth=3):
    if depth <= 0:
        return rng.choice((str(rng.randint(-1000, 1000)), json.dumps(rng.choice(("", "hi", "λ", "a\nb", "\"\\")), ensure_ascii=False), "{}", "[]", "todo"))
    expr = lambda: generated_source(rng, depth - 1)
    choice = rng.randrange(10)
    if choice == 0:
        return f"let x = {expr()} x"
    if choice == 1:
        return f"(x, y) -> {{ {expr()} }}"
    if choice == 2:
        return f"!int_add({expr()}, {expr()})"
    if choice == 3:
        return f"{{foo: {expr()}, bar: {expr()}}}"
    if choice == 4:
        return f"[{expr()}, {expr()}]"
    if choice == 5:
        return f"Some({expr()})"
    if choice == 6:
        return f"match Some({expr()}) {{ Some(x) -> {{ x }} | (_) -> {{ {expr()} }} }}"
    if choice == 7:
        return f"perform StandardOut({expr()})"
    if choice == 8:
        return f"((x) -> {{ x }})({expr()})"
    return f"{{foo: {expr()}}}.foo"


def generated_edit_source(rng, depth=3, kind=None):
    """Closed, type-consistent programs give navigation a substantial AST."""
    kind = kind or rng.choice(("int", "string", "record", "list", "function"))
    if depth <= 0:
        if kind == "string":
            return json.dumps(rng.choice(("hello", "λ", "界", "a\nb", "é")), ensure_ascii=False)
        return str(rng.randrange(-100, 100))
    integer = lambda: generated_edit_source(rng, depth - 1, "int")
    string = lambda: generated_edit_source(rng, depth - 1, "string")
    if kind == "int":
        choice = rng.randrange(8)
        if choice == 0:
            return f"!int_add({integer()}, {integer()})"
        if choice == 1:
            return f"((x) -> {{ !int_add(x, {rng.randrange(10)}) }})({integer()})"
        if choice == 2:
            return f"let x = {integer()} !int_multiply(x, 2)"
        if choice == 3:
            return f"{{answer: {integer()}, name: {string()}}}.answer"
        if choice == 4:
            return f"match Some({integer()}) {{ Some(x) -> {{ x }} | (_) -> {{ 0 }} }}"
        if choice == 6:
            return f"let {{x, y: z}} = {{x: {integer()}, y: {integer()}}} !int_add(x, z)"
        if choice == 7:
            return f"(({{x, y: z}}) -> {{ !int_add(x, z) }})({{x: {integer()}, y: {integer()}}})"
        return f"!list_fold([{integer()}, {integer()}], 0, (x, acc) -> {{ !int_add(x, acc) }})"
    if kind == "string":
        return f"!string_append({string()}, {string()})" if rng.randrange(2) else f"!int_to_string({integer()})"
    if kind == "record":
        return f"{{count: {integer()}, name: {string()}, items: [{integer()}, {integer()}]}}"
    if kind == "list":
        return f"[{integer()}, {integer()}, {integer()}]"
    return f"(x) -> {{ !int_add(x, {integer()}) }}"


def generated_program_edit_trace(rng, length):
    navigation = ("left", "right", "right", "right", "up", "down", "a", " ", "k")
    editing = ("i", "o", "x", "<", ">", "c", "C", "g", "e", "E", "f", "l", "r", "m", "d", "z", "Z")
    events = []
    for _ in range(length):
        choice = rng.randrange(10)
        if choice < 6:
            events.append({"key": rng.choice(navigation)})
        elif choice < 9:
            events.append({"key": rng.choice(editing)})
        else:
            events.append(rng.choice([{"key": "enter"}, {"key": "esc"}, {"key": "tab"}, {"paste": "field"}, {"paste": "7"}]))
    return events


SYNTAX_CASES = [
    "42", "-42", '"hello\\nworld"', "todo", "let x = 1 x", "let x = 1 let x = 2 x",
    "(x, y) -> { !int_add(x, y) }", "let {x, y: z} = {x: 1, y: 2} z",
    "({name, age: n}) -> { name }", "{}", "{x: 1, y: 2}", "{x: 1}.x", "[1, 2, 3]",
    "Some(42)", "match Some(1) { Some(x) -> { x } | (_) -> { 0 } }",
    "perform StandardOut(\"hello\")", "let module = import \"./foo.eyg\" module.x",
    "@standard", "@standard:1", "// hi\nlet x = 1 // comment\nx",
    "!fix((self, n) -> { match !int_compare(n, 0) { Eq(_) -> { 1 } | (_) -> { !int_multiply(n, self(!int_subtract(n, 1))) } } })(5)",
]

DIAGNOSTIC_CASES = ["let x 1", "let x =", "(x) { x }", "(x) -> { x", "perform x", "!", "#bad", "@foo:nope",
                    "import 1", "import", "1 2", "§", '"unterminated', '"bad\\q"', "9007199254740992",
                    "let x = 1\nlet y 2", "let λ = 1", "match X(1) { X(x) { x } }", "{x:", "[1, 2",
                    "@", "#", "(x) -> { let y 2 }", '"λ\\q"', "// hi\nlet x 1"]


def tui_scenarios():
    key = lambda x: {"key": x}
    record = "{x: 1, y: 2}"
    match = "match Some(1) { Some(x) -> { x } | (_) -> { 0 } }"
    binary = lambda encoded: [{"paste": json.dumps({"0": "x", "v": {"/": {"bytes": encoded}}})}, key("enter")]
    field_edit = lambda side: [{"paste": record}, key("right"), key(side), {"paste": "added"}, key("enter"), key("n"), {"paste": "9"}, key("enter"), key("a"), key("enter")]
    branch_edit = lambda side: [{"paste": match}, key("right"), key("right"), key("right"), key(side), {"paste": "Other"}, key("enter"), key("esc"), key("a")]
    long_input = lambda text: [key("s"), {"paste": text}, key("home"), key("right"), key("end"), key("enter"), key("enter")]
    return {
        "empty": [],
        "integer-input": list(map(key, ("n", "1", "2", "backspace", "3", "left", "4", "enter", "enter"))),
        "invalid-integer": list(map(key, ("n", "backspace", "-", "enter", "esc"))),
        "string-unicode": [key("s"), {"paste": "hello λ👩‍💻é\nworld"}, key("enter"), key("enter")],
        "arithmetic-paste": [{"paste": "!int_add(20, 22)"}, key("enter")],
        "history-source-lifetime": [{"paste": "!int_add(20, 22)"}, key("enter"), key("s"), {"paste": "hello λé"}, key("enter"), key("enter")],
        "multiline-history": [{"paste": "let x = 1 let y = 2 !int_add(x, y)"}, key("enter"), key("up"), key("k"), key("K"), key("k"), key("esc")],
        "expanded-effect-history": [{"paste": 'let _ = perform StandardOut("hello") let _ = perform Sleep(1) 42'}, key("enter"), key("up"), key("K"), key("k"), key("K"), key("esc")],
        "scope-history": [{"paste": "let x = 42 x"}, key("enter"), {"paste": "x"}, key("enter"), key("up"), key("up"), key("down"), key("enter")],
        "history-recall": [{"paste": "[1, 2, 3]"}, key("enter"), key("up"), key("enter"), key("esc")],
        "builtin-picker": list(map(key, ("j", "i", "n", "t", "_", "a", "down", "up", "tab", "enter"))),
        "record-list": list(map(key, ("R", "r", "x", "enter", "n", "3", "enter", "esc", "L"))),
        "function-edit": list(map(key, ("f", "x", "enter", "n", "5", "enter", "a", "left", "right", "up", "down"))),
        "delete-undo": [{"paste": "{x: 1, y: [2, 3]}"}, *map(key, ("right", "d", "u", "ctrl+z", "ctrl+y"))],
        "standard-input": [{"paste": "perform StandardIn({})"}, key("enter"), {"paste": "hello"}, key("enter")],
        "standard-input-cancel": [{"paste": "perform StandardIn({})"}, key("enter"), key("esc")],
        "resize": [{"resize": [20, 5]}, key("n"), {"resize": [120, 40]}, key("esc"), {"resize": [1, 1]}, {"resize": [80, 24]}],
        "invalid-paste": [{"paste": "this is not valid eyg !!"}, key("enter"), key("esc")],
        "unknown-keys": list(map(key, ("?", "ctrl+x", "home", "end", "pageup", "esc"))),
        "binary-ir-aqid": binary("AQID"),
        "binary-ir-ascii-padded": binary("aGVsbG8="),
        "binary-ir-unicode": binary(base64.b64encode("λ界".encode()).decode()),
        "destructured-let": [{"paste": "let {x, y: z} = {x: 20, y: 22} !int_add(x, z)"}, key("right"), key("down"), key("a"), key("enter"), {"paste": "!int_add(x, z)"}, key("enter")],
        "destructured-lambda": [{"paste": "({x}) -> { x }"}, key("right"), key("right"), key("left"), key("a")],
        "destructured-lambda-run": [{"paste": "(({x, y: z}) -> { !int_add(x, z) })({x: 20, y: 22})"}, key("enter")],
        "whole-record-lambda": [{"paste": "(r) -> { let x = r.x r }"}, key("right"), key("right"), key("a")],
        "selector-let-pattern": [{"paste": "let value = {x: 20, y: 22} let x = value.x let z = value.y !int_add(x, z)"}, key("enter")],
        "empty-destructure": [{"paste": "let {} = {x: 1} 42"}, key("enter"), {"paste": "({}) -> { 42 }"}, key("right")],
        "field-before": field_edit("<"),
        "field-after": field_edit(">"),
        "branch-before": branch_edit("<"),
        "branch-after": branch_edit(">"),
        "long-ascii-input": long_input("x" * 300),
        "long-cjk-input": long_input("界" * 150),
        "long-combining-input": long_input("é" * 300),
        "input-cell-boundary-overshoot": long_input("x" * 255 + "界Z"),
        "wide-cursor-input-edit": [key("s"), {"paste": "界x"}, key("left"), key("left"), key("z"), key("w"), key("backspace"), key("enter"), key("enter")],
        "returned-resumption": [{"paste": json.dumps(returned_resumption_program())}, key("enter")],
        "unicode-record-key-order": [{"paste": json.dumps(unicode_record_program(), ensure_ascii=False)}, key("enter")],
        "primitive-select": [{"paste": json.dumps(node("g", l="answer"))}, key("right"), key("left"), key("enter")],
        "primitive-select-apply": [{"paste": json.dumps(call(node("g", l="answer"), call(node("e", l="answer"), node("i", v=42), node("u"))))}, key("enter")],
        "primitive-partial-case": [{"paste": json.dumps(call(node("m", l="Some"), node("f", l="x", b=node("v", l="x"))))}, key("right"), key("left"), key("enter")],
        "primitive-case-apply": [{"paste": json.dumps(call(node("m", l="Some"), node("f", l="x", b=node("v", l="x")), node("n"), call(node("t", l="Some"), node("i", v=42))))}, key("enter")],
        "primitive-bare-case": [{"paste": json.dumps(node("m", l="Some"))}, key("enter")],
        "primitive-bare-no-cases": [{"paste": json.dumps(node("n"))}, key("enter")],
        "multiline-first-call-argument": [{"paste": "f(match Some(1) { Some(x) -> { x } | (_) -> { 0 } }, 2)"}, key("right"), key("right")],
        "multiline-final-call-argument": [{"paste": "f(2, match Some(1) { Some(x) -> { x } | (_) -> { 0 } })"}, key("right"), key("right")],
        "multiline-match-subject": [{"paste": "match (match Some(1) { Some(x) -> { Some(x) } | (_) -> { Some(0) } }) { Some(x) -> { x } | (_) -> { 0 } }"}, key("right")],
    }


def generated_trace(rng, length=25):
    keys = ["n", "s", "j", "f", "r", "R", "l", "L", "i", "e", "E", "w", "g", "t", "p", "h", "o", "d", "a", "k",
            "q", "@", "#", "z", "Z", "x", "c", "C", "b", "m", "v", "<", ">", "y", "Y", "K",
            "left", "right", "up", "down", "enter", "esc", "tab", "backspace", "delete", "home", "end", "ctrl+a", "ctrl+e", "ctrl+k", "ctrl+u", "?", "1", "x", "_", " "]
    events = []
    for _ in range(length):
        n = rng.randrange(20)
        if n == 0:
            events.append({"resize": [rng.choice([1, 20, 40, 80, 100, 120]), rng.choice([1, 3, 5, 10, 24, 40])]})
        elif n < 4:
            events.append({"paste": rng.choice(["42", '!int_add(20, 22)', '"hello λ"', "let x = 2 x", "[1, 2, 3]", "{x: 1, y: 2}", "todo", "invalid!!", "👩‍💻é"])})
        else:
            events.append({"key": rng.choice(keys)})
    return events


def first_difference(expected, got, path="$"):
    # JSON has one Number type. Decimal and exponent spellings round to the
    # same IEEE-754 value in the JavaScript oracle; Python's parser happens to
    # distinguish int and float tokens. Booleans remain a separate JSON type.
    numbers = (int, float)
    if isinstance(expected, numbers) and not isinstance(expected, bool) and isinstance(got, numbers) and not isinstance(got, bool):
        try:
            if float(expected) == float(got):
                return None
        except OverflowError:
            pass
        return {"path": path, "expected": expected, "got": got}
    if type(expected) is not type(got):
        return {"path": path, "expected": expected, "got": got}
    if isinstance(expected, dict):
        if expected.keys() != got.keys():
            return {"path": path, "expected_keys": sorted(expected), "got_keys": sorted(got)}
        for key in expected:
            difference = first_difference(expected[key], got[key], f"{path}.{key}")
            if difference:
                return difference
    elif isinstance(expected, list):
        if len(expected) != len(got):
            return {"path": path, "expected_length": len(expected), "got_length": len(got)}
        for i, (e, g) in enumerate(zip(expected, got)):
            difference = first_difference(e, g, f"{path}[{i}]")
            if difference:
                return difference
    elif expected != got:
        return {"path": path, "expected": expected, "got": got}
    return None


def same(expected, got):
    return first_difference(expected, got) is None


def shrink_program(program, fails):
    """Greedy tree/constant shrinking; every candidate is rerun in both engines."""
    current = program
    for _ in range(50):
        candidates = [node("i", v=0), node("u"), node("ta")]
        if isinstance(current, dict):
            candidates += [v for v in current.values() if isinstance(v, dict) and "0" in v]
            for key, child in current.items():
                if isinstance(child, dict) and "0" in child:
                    candidates.append({**current, key: node("i", v=0)})
        smaller = [c for c in candidates if len(json.dumps(c)) < len(json.dumps(current))]
        replacement = next((c for c in smaller if fails(c)), None)
        if replacement is None:
            break
        current = replacement
    return current


def shrink_events(events, fails):
    """Delta debugging removes chunks while retaining an observed mismatch."""
    current, granularity = list(events), 2
    if fails([]):
        return []
    while current:
        size = max(1, (len(current) + granularity - 1) // granularity)
        for start in range(0, len(current), size):
            candidate = current[:start] + current[start + size:]
            if fails(candidate):
                current, granularity = candidate, max(2, granularity - 1)
                break
        else:
            if granularity >= len(current):
                break
            granularity = min(len(current), granularity * 2)
    return current


def main():
    args = argparse.ArgumentParser(description=__doc__)
    args.add_argument("--binary", type=Path, default=PACKAGE / "zig-out/bin/eyg")
    args.add_argument("--bun", default=os.environ.get("BUN") or shutil.which("bun") or "/workspace/tooling/bin/bun")
    args.add_argument("--seed", type=int, default=20261028)
    args.add_argument("--programs", type=int, default=1000)
    args.add_argument("--syntax", type=int, default=200)
    args.add_argument("--traces", type=int, default=100)
    args.add_argument("--trace-length", type=int, default=25)
    args.add_argument("--edit-traces", type=int, help="nested-program editing traces; defaults to --traces")
    args.add_argument("--edit-length", type=int, default=20)
    args.add_argument("--only", choices=("eval", "parse", "tui"))
    args.add_argument("--scenario", help="run one named TUI scenario")
    args.add_argument("--named-only", action="store_true", help="run only the fixed TUI scenarios")
    args.add_argument("--edit-only", action="store_true", help="run only generated nested-program editing traces")
    args.add_argument("--replay", type=Path)
    args.add_argument("--report", type=Path, default=PACKAGE / "reports/differential.json")
    args.add_argument("--no-shrink", action="store_true")
    args.add_argument("--oracle-timeout", type=float, default=30, help="seconds per oracle response; a timeout is retained as a failure and the oracle is restarted")
    options = args.parse_args()
    if options.edit_traces is None:
        options.edit_traces = options.traces
    if options.named_only:
        options.only, options.traces, options.edit_traces = "tui", 0, 0
    if options.edit_only:
        options.only, options.traces = "tui", 0
    options.report = options.report.resolve()
    actual_sha = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ORACLE, text=True).strip()
    if actual_sha != ORACLE_SHA:
        raise SystemExit(f"oracle revision is {actual_sha}; expected {ORACLE_SHA}")
    if subprocess.run(["git", "diff", "--quiet", "HEAD", "--"], cwd=ORACLE).returncode:
        raise SystemExit("oracle tracked sources are modified")
    native = Peer([str(options.binary.resolve()), "--protocol"])
    oracle = Peer([options.bun, str(PACKAGE / "tests/oracle.mjs")], timeout=options.oracle_timeout)
    report = {"seed": options.seed, "oracle": ORACLE_SHA,
              "binary_sha256": hashlib.sha256(options.binary.read_bytes()).hexdigest(),
              "oracle_manifest_sha256": hashlib.sha256((ORACLE / "packages/gleam_cli/manifest.toml").read_bytes()).hexdigest(),
              "command": sys.argv, "comparison": "Exact object keys, arrays, strings and buffer cells; JSON Numbers compare by JavaScript IEEE-754 value, with booleans separate. Rendered text is never normalized.", "rng_streams": {"programs": options.seed, "syntax": options.seed + 1, "behaviour": options.seed, "program_edits": options.seed + 2}, "passed": False, "status": "running", "counts": {}, "failures": [], "sensitivity": {}, "coverage": {"ir_nodes": {}, "builtins": {}}, "peer_failures": [], "oracle_timeout_seconds": options.oracle_timeout}
    node_coverage, builtin_coverage = Counter(), Counter()
    rng = random.Random(options.seed)
    artifact_dir = options.report.parent / "failures"
    started = time.monotonic()
    shrink_categories = set()
    options.report.parent.mkdir(parents=True, exist_ok=True)
    options.report.write_text(json.dumps(report, ensure_ascii=True, indent=2) + "\n")

    def save_report():
        options.report.write_text(json.dumps(report, ensure_ascii=True, indent=2) + "\n")

    def save_failure(category, name, request, failure, minimized=None):
        artifact_dir.mkdir(parents=True, exist_ok=True)
        identity = hashlib.sha256(json.dumps(request, sort_keys=True, ensure_ascii=True).encode()).hexdigest()[:10]
        path = artifact_dir / f"{category}-{options.seed}-{report['binary_sha256'][:8]}-{identity}.json"
        path.write_text(json.dumps({"seed": options.seed, "oracle": ORACLE_SHA,
            "binary_sha256": report["binary_sha256"], "category": category, "name": name,
            "request": request, "minimized": minimized or request, "failure": failure}, ensure_ascii=True, indent=2) + "\n")
        failure["reproducer"] = str(path.relative_to(PACKAGE)) if path.is_relative_to(PACKAGE) else str(path)
        report["failures"].append(failure)
        save_report()

    def exchange(peer, request):
        try:
            response = peer.request(request)
            if isinstance(response, dict) and "adapter_error" in response:
                raise RuntimeError(str(response))
            return response, None
        except (TimeoutError, RuntimeError, OSError, ValueError) as error:
            detail = {"kind": "timeout" if isinstance(error, TimeoutError) else "exception", "error": str(error)}
            peer.restart()
            return None, detail

    def check(category, name, request, expected_fixture=None):
        if request["op"] == "tui":
            request = {"files": {}, **request}
        def coverage(value):
            if isinstance(value, dict):
                if "0" in value:
                    node_coverage[value["0"]] += 1
                    if value["0"] == "b":
                        builtin_coverage[value["l"]] += 1
                for child in value.values():
                    coverage(child)
            elif isinstance(value, list):
                for child in value:
                    coverage(child)
        if "program" in request:
            coverage(request["program"])
        counter = report["counts"].setdefault(category, {"checked": 0, "compared": 0, "passed": 0, "failed": 0, "uncomparable": 0})
        counter["checked"] += 1
        # Ask both independently: an oracle timeout is not evidence that native
        # matched it. Keep the request and continue with a fresh oracle process.
        got, native_error = exchange(native, request)
        expected, oracle_error = exchange(oracle, request)
        if native_error or oracle_error:
            counter["failed"] += 1
            counter["uncomparable"] += 1
            failure = {"category": category, "name": name, "request": request,
                       "native_error": native_error, "oracle_error": oracle_error}
            report["peer_failures"].append({k: v for k, v in failure.items() if k != "request"})
            save_failure(category, name, request, failure)
            print(f"UNCOMPARABLE {category}/{name}: {oracle_error or native_error}", file=sys.stderr)
            return
        counter["compared"] += 1
        if expected_fixture is not None and not same(expected, expected_fixture):
            raise AssertionError(f"oracle fixture self-check failed for {name}: {expected} != {expected_fixture}")
        if same(expected, got):
            counter["passed"] += 1
            if counter["checked"] % 25 == 0:
                save_report()
            return
        counter["failed"] += 1
        failure = {"category": category, "name": name, "difference": first_difference(expected, got), "request": request}
        # Shrinking only retains a finite, observed comparison mismatch. A hang
        # encountered during shrinking never replaces the original mismatch.
        def differs(candidate):
            actual, n_error = exchange(native, candidate)
            reference, o_error = exchange(oracle, candidate)
            return not (n_error or o_error) and not same(reference, actual)
        minimized = request
        if category not in shrink_categories and not options.no_shrink:
            shrink_categories.add(category)
            if request["op"] == "eval":
                minimized = {**request, "program": shrink_program(request["program"], lambda p: differs({**request, "program": p}))}
            elif request["op"] == "tui":
                minimized = {**request, "events": shrink_events(request["events"], lambda e: differs({**request, "events": e}))}
        save_failure(category, name, request, failure, minimized)
        if counter["failed"] <= 5:
            print(f"FAIL {category}/{name}: {ascii(failure['difference'])}", file=sys.stderr)

    try:
        # Sensitivity checks are against the comparator itself, before native
        # tests. A one-cell symbol/style/width mutation must not compare equal.
        probe = oracle.request({"op": "tui", "width": 20, "height": 5, "events": []})
        for field, changed in (("symbol", "X"), ("fg", 4), ("modifiers", 32), ("width", 2), ("underline_color", 1), ("link", "https://example.com")):
            mutated = json.loads(json.dumps(probe))
            mutated["frames"][0]["cells"][0][field] = changed
            report["sensitivity"][field] = first_difference(probe, mutated) is not None
        assert all(report["sensitivity"].values())
        report["sensitivity"]["json_types"] = not same({"integer": 1}, {"integer": True})
        assert report["sensitivity"]["json_types"]
        report["sensitivity"]["number_difference"] = not same(1, 1.5)
        report["sensitivity"]["numeric_string"] = not same("1", 1)
        report["sensitivity"]["number_token_equivalence"] = same(10**20, 1e20)
        assert all(report["sensitivity"].values())

        if options.replay:
            saved = json.loads(options.replay.read_text())
            request = saved.get("minimized", saved.get("request", saved))
            check("replay", options.replay.name, request)
        else:
            if options.only in (None, "eval"):
                for path in sorted((ORACLE / "spec/evaluation").glob("*_suite.json")):
                    for fixture in json.loads(path.read_text()):
                        expected = {"value": fixture["value"]} if "value" in fixture else {"break": fixture["break"]}
                        check("spec", fixture["name"], {"op": "eval", "program": fixture["source"], "effects": fixture.get("effects", [])}, expected)
                for i in range(options.programs):
                    check("generated-program", str(i), {"op": "eval", "program": generated_program(rng)})
                    if i % 10 == 0:
                        first, second = rng.randrange(-100, 100), rng.randrange(-100, 100)
                        source = node("l", l="a", v=call(node("p", l="First"), node("i", v=1)),
                                      t=node("l", l="b", v=call(node("p", l="Second"), node("v", l="a")), t=builtin("int_add", node("v", l="a"), node("v", l="b"))))
                        check("generated-external-effects", str(i), {"op": "eval", "program": source, "effects": [
                            {"label": "First", "lift": {"integer": 1}, "reply": {"integer": first}},
                            {"label": "Second", "lift": {"integer": first}, "reply": {"integer": second}}]})
                    if i % 20 == 0:
                        lift_ir, lift = literal_fixture(rng)
                        _, first = literal_fixture(rng)
                        _, second = literal_fixture(rng)
                        source = node("l", l="a", v=call(node("p", l="First"), lift_ir), t=call(node("p", l="Second"), node("v", l="a")))
                        check("generated-external-values", str(i), {"op": "eval", "program": source, "effects": [
                            {"label": "First", "lift": lift, "reply": first}, {"label": "Second", "lift": first, "reply": second}]})
            if options.only in (None, "parse"):
                rng = random.Random(options.seed + 1)
                for i, source in enumerate(SYNTAX_CASES):
                    check("syntax-fixture", str(i), {"op": "parse", "source": source})
                for i, source in enumerate(DIAGNOSTIC_CASES):
                    check("diagnostic-fixture", str(i), {"op": "diagnostic", "source": source})
                for i in range(options.syntax):
                    check("generated-syntax", str(i), {"op": "parse", "source": generated_source(rng)})
                real = REPO / "work/oracle-real-world/dark"
                for path in sorted(real.glob("git/*.eyg")):
                    check("real-world-syntax", path.name, {"op": "parse", "source": path.read_text()})
            if options.only in (None, "tui"):
                rng = random.Random(options.seed)
                scenarios = {} if options.edit_only else tui_scenarios()
                if options.scenario:
                    scenarios = {options.scenario: scenarios[options.scenario]}
                for name, events in scenarios.items():
                    check("tui-scenario", name, {"op": "tui", "width": 80, "height": 24, "events": events})
                if not options.scenario and not options.named_only and not options.edit_only:
                    files = {"lib/answer.eyg": "42", "main.eyg": "{answer: 42}", ".hidden.eyg": "0"}
                    fixture_scenarios = {
                        "import-picker": [{"key": "q"}, {"paste": "lib/answer.eyg"}, {"key": "enter"}, {"key": "enter"}],
                        "import-hidden": [{"key": "q"}, {"key": "."}, {"key": "down"}, {"key": "esc"}],
                        "import-directory": [{"key": "q"}, {"paste": "lib/"}, {"key": "enter"}, {"key": "esc"}],
                        "import-expression": [{"paste": 'import "lib/answer.eyg"'}, {"key": "enter"}],
                        "import-missing": [{"paste": 'import "missing.eyg"'}, {"key": "enter"}],
                        "package-empty": [{"key": "@"}, {"key": "tab"}, {"key": "enter"}, {"key": "esc"}],
                        "cid-invalid": [{"key": "#"}, {"paste": "bad-cid"}, {"key": "enter"}, {"key": "esc"}],
                        "sandbox-cwd": [{"paste": "perform Cwd({})"}, {"key": "enter"}, {"key": "up"}, {"key": "K"}],
                        "sandbox-now": [{"paste": "perform Now({})"}, {"key": "enter"}],
                        "sandbox-stdout": [{"paste": 'perform StandardOut("hello")'}, {"key": "enter"}, {"key": "up"}, {"key": "K"}],
                        "sandbox-sleep": [{"paste": "perform Sleep(1)"}, {"key": "enter"}],
                    }
                    for name, events in fixture_scenarios.items():
                        check("tui-world", name, {"op": "tui", "width": 80, "height": 24, "files": files, "events": events})
                    for name, code in (("import-unhandled-stdin", "perform StandardIn({})"), ("import-unhandled-stdout", 'perform StandardOut("hello")')):
                        check("tui-world", name, {"op": "tui", "width": 80, "height": 24, "files": {"ask.eyg": code}, "events": [{"paste": 'import "ask.eyg"'}, {"key": "enter"}]})
                    check("tui-world", "import-exported-effect", {"op": "tui", "width": 80, "height": 24,
                        "files": {"callable.eyg": '(_) -> { perform StandardOut("hello") }'},
                        "events": [{"paste": 'let run = import "callable.eyg" run({})'}, {"key": "enter"}, {"key": "up"}, {"key": "K"}]})
                    for name, expression in {
                        "sleep-type": 'perform Sleep("bad")',
                        "readfile-missing": 'perform ReadFile({})',
                        "readfile-first-field": 'perform ReadFile({limit: {}, offset: "bad", path: 1})',
                        "readfile-offset": 'perform ReadFile({path: "main.eyg", offset: "bad", limit: 1})',
                        "readfile-limit": 'perform ReadFile({path: "main.eyg", offset: 0, limit: "bad"})',
                        "fetch-missing": 'perform Fetch({})',
                        "fetch-nested-header": 'perform Fetch({method: GET({}), scheme: HTTP({}), host: "localhost", port: None({}), path: "/", query: None({}), headers: [{value: "ok", key: 1}], body: !binary_from_integers([])})',
                        "fetch-unit-payload": 'perform Fetch({method: GET("bad"), scheme: HTTP({})})',
                        "stdin-type": 'perform StandardIn("bad")',
                        "stdin-extra-unit-field": 'perform StandardIn({unexpected: 1})',
                        "stdout-type": 'perform StandardOut(42)',
                        "stderr-type": 'perform StandardError({})',
                        "exit-type": 'perform Exit("bad")',
                        "hash-unit-payload": 'perform Hash({algorithm: SHA256("bad"), bytes: !binary_from_integers([])})',
                        "sign-field-order": 'perform Sign({key: "bad", data: 1})',
                    }.items():
                        check("tui-effect-cast", name, {"op": "tui", "width": 80, "height": 24, "files": files,
                            "events": [{"paste": expression}, {"key": "enter"}, {"key": "up"}, {"key": "K"}]})
                    for extension, module in (("text", '(_) -> { perform Ping(1) }'), ("json", json.dumps(node("f", l="_", b=call(node("p", l="Ping"), node("i", v=1)))))):
                        imported_resume = call(node("h", l="Ping"), node("f", l="x", b=node("f", l="resume", b=node("v", l="resume"))), node(".", i="closure.eyg"))
                        check("tui-world", "import-resumption-" + extension, {"op": "tui", "width": 120, "height": 40,
                            "files": {"closure.eyg": module}, "events": [{"paste": json.dumps(imported_resume)}, {"key": "enter"}, {"key": "up"}, {"key": "K"}, {"key": "k"}, {"resize": [40, 24]}]})
                    packages = {
                        "alpha": {"version": 3, "program": node("i", v=7)},
                        "demo": {"version": 1, "program": node("i", v=42)},
                        "record": {"version": 2, "program": call(node("e", l="answer"), node("i", v=42), node("u"))},
                        "succ": {"version": 1, "program": node("f", l="x", b=builtin("int_add", node("v", l="x"), node("i", v=1)))},
                    }
                    metadata = oracle.request({"op": "package_metadata", "packages": packages})
                    cids = {p["name"]: p["cid"] for p in metadata["packages"]}
                    hub_scenarios = {
                        "release-picker": [{"key": "@"}, {"key": "tab"}, {"key": "enter"}, {"key": "enter"}],
                        "floating": [{"paste": "@demo"}, {"key": "enter"}],
                        "version": [{"paste": "@demo:1"}, {"key": "enter"}],
                        "pinned": [{"paste": "@demo:1:" + cids["demo"]}, {"key": "enter"}],
                        "mismatched-pin": [{"paste": "@demo:1:" + cids["alpha"]}, {"key": "enter"}],
                        "content": [{"paste": "#" + cids["demo"]}, {"key": "enter"}],
                        "record-field": [{"paste": "@record.answer"}, {"key": "enter"}],
                        "function": [{"paste": "@succ(41)"}, {"key": "enter"}],
                    }
                    for name, events in hub_scenarios.items():
                        check("tui-hub", name, {"op": "tui", "width": 80, "height": 24, "packages": packages, "events": events})
                for i in range(options.traces):
                    check("generated-behaviour", str(i), {"op": "tui", "width": rng.choice((20, 40, 80, 120)), "height": rng.choice((5, 10, 24, 40)), "events": generated_trace(rng, options.trace_length)})
                if not options.scenario and not options.named_only:
                    edit_rng = random.Random(options.seed + 2)
                    for i in range(options.edit_traces):
                        # The independent Gleam parser filters candidates; the
                        # generated text is then pasted into both real reducers.
                        for _ in range(100):
                            source = generated_edit_source(edit_rng)
                            if "program" in oracle.request({"op": "parse", "source": source}):
                                break
                        else:
                            raise RuntimeError("nested source grammar generated no parseable program")
                        events = [{"paste": source}, *generated_program_edit_trace(edit_rng, options.edit_length)]
                        check("generated-program-edit", str(i), {"op": "tui", "width": edit_rng.choice((40, 80, 120)), "height": edit_rng.choice((10, 24, 40)), "events": events})
        report["passed"] = all(c["failed"] == 0 for c in report["counts"].values())
        report["status"] = "complete"
    finally:
        native.close()
        oracle.close()
        report["elapsed_seconds"] = time.monotonic() - started
        report["coverage"] = {"ir_nodes": dict(sorted(node_coverage.items())), "builtins": dict(sorted(builtin_coverage.items()))}
        options.report.parent.mkdir(parents=True, exist_ok=True)
        options.report.write_text(json.dumps(report, ensure_ascii=True, indent=2) + "\n")
    print(json.dumps({"report": str(options.report), "passed": report.get("passed", False), "counts": report["counts"]}))
    return 0 if report.get("passed") else 1


if __name__ == "__main__":
    sys.exit(main())
