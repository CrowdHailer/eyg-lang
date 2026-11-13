#!/usr/bin/env python3
"""Compare pure computer effects with their actual pinned Gleam handlers."""
import argparse
import base64
from collections import Counter
import hashlib
import json
from pathlib import Path
import random
import shutil
import sys

from differential import PACKAGE, ORACLE_SHA, Peer, first_difference, generated_source, node, call, builtin


def binary(data):
    return {"binary": {"/": {"bytes": base64.b64encode(data).decode().rstrip("=")}}}


def signing(seed, message):
    return {"label": "Sign", "lift": {"record": {
        "key": {"tagged": {"label": "Eddsa", "value": {"record": {"d": binary(seed)}}}},
        "data": binary(message),
    }}}


def unwrap(tag, value):
    return call(node("m", l=tag), node("f", l="payload", b=node("v", l="payload")), node("n"), value)


def json_term(raw):
    parsed = unwrap("Ok", call(node("p", l="DecodeJSON"), node("x", v=binary(raw)["binary"])))
    popped = unwrap("Ok", builtin("list_pop", parsed))
    return call(node("g", l="term"), call(node("g", l="head"), popped))


def parsed_integer(raw):
    return unwrap("Integer", json_term(raw))


def json_value(rng, depth=3):
    if depth <= 0:
        return rng.choice([None, True, False, rng.randint(-100000, 100000), rng.choice(["", "λ", "\0\r\n", "👩🏽‍💻", "é", "quote\"\\"])])
    kind = rng.randrange(4)
    if kind == 0:
        return [json_value(rng, depth - 1) for _ in range(rng.randrange(5))]
    if kind == 1:
        return {key: json_value(rng, depth - 1) for key in rng.sample(["x", "y", "a", "λ", "name"], rng.randrange(5))}
    return json_value(rng, 0)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--binary", type=Path, default=PACKAGE / "work/computer-check")
    parser.add_argument("--bun", default=shutil.which("bun") or "/workspace/tooling/bin/bun")
    parser.add_argument("--seed", type=int, default=20261028)
    parser.add_argument("--cases", type=int, default=1000)
    parser.add_argument("--report", type=Path, default=PACKAGE / "reports/computer.json")
    args = parser.parse_args()
    rng = random.Random(args.seed)
    native = Peer([str(args.binary.resolve())])
    oracle = Peer([args.bun, str(PACKAGE / "tests/computer_oracle.mjs")])
    counts = Counter()
    report = {"oracle": ORACLE_SHA, "seed": args.seed, "binary_sha256": hashlib.sha256(args.binary.read_bytes()).hexdigest(), "failures": []}

    def compare(request):
        expected, got = oracle.request(request), native.request(request)
        counts[request.get("label", "unsafe-program")] += 1
        if expected != got:
            if len(report["failures"]) < 20:
                report["failures"].append({"request": request, "difference": first_difference(expected, got), "expected": expected, "got": got})
            return False
        return True

    try:
        raw_cases = [b"", b" ", b"[", b"{", b"-", b"1.", b"1e", b"1e+", b"1e-", b"01", b"1 garbage", b"truefalse", b"[1,]", b'{"x":1,}', b'{"x":1,"x":2}', b"-0.000e-0", b"9007199254740993", b'"\\uD83D\\uDE80"', b'"\\uD800"', b'"\\uDC00"', b'"\\u123"', b'"\\u+123"', b'"\\q"', b'"\\', b'"raw\nline"', b'"\xff"', b"\xff"]
        raw_cases += [b'"' + b'\xff' * 64 + b'"', b'"\xc3"', b'{"x":"\xc3"}']
        for _ in range(args.cases):
            encoded = json.dumps(json_value(rng), ensure_ascii=rng.choice([True, False]), separators=(",", ":")).encode()
            raw_cases.append(encoded)
            raw_cases.append(encoded[:rng.randrange(len(encoded) + 1)])
        for _ in range(args.cases):
            sign = rng.choice(["", "-"])
            decimal = rng.choice(["", "." + str(rng.randrange(100000)).zfill(rng.randrange(1, 8))])
            exponent = rng.choice(["", "e+0", "e" + str(rng.randint(-100, 100)), "E-03"])
            raw_cases.append(f"{sign}{rng.randrange(10000)}{decimal}{exponent}".encode())
        for raw in raw_cases:
            compare({"label": "DecodeJSON", "lift": binary(raw)})
        for _ in range(args.cases // 2):
            compare({"label": "DecodeJSON", "lift": binary(str(rng.randrange(10**16, 10**18)).encode())})
        huge = ["9" * 400, "-" + "9" * 400, "9223372036854775808", "-9223372036854775808", "18446744073709551616", "1" + "0" * 100]
        for raw in huge + ["1." + "9" * 400 + "e-" + "9" * 400]:
            compare({"label": "DecodeJSON", "lift": binary(raw.encode())})

        # Obtain unsafe Integer values through the actual host effect, then
        # apply language operations. This checks behavior beyond wire printing.
        raw_numbers = [str(n) for n in [0, 9007199254740991, 9007199254740992, (1 << 63) - 1024, 1 << 63, -(1 << 63), 1 << 64, -(1 << 64)]]
        raw_numbers += huge + [str(rng.randrange(10**16, 10**18)) for _ in range(20)]
        n = node("v", l="number")
        self_divided = unwrap("Ok", builtin("int_divide", n, n))
        operations = [builtin("int_to_string", n), builtin("int_absolute", n), builtin("int_compare", n, node("i", v=9007199254740991)), builtin("int_add", n, node("i", v=1)), builtin("int_subtract", n, n), builtin("int_multiply", n, node("i", v=0)), builtin("int_divide", n, node("i", v=3)), builtin("int_divide", n, n), builtin("equal", n, n), builtin("binary_from_integers", call(node("c"), n, node("ta"))), builtin("int_parse", builtin("int_to_string", n)), builtin("int_to_string", self_divided), builtin("int_compare", self_divided, self_divided), builtin("equal", self_divided, self_divided)]
        for raw in raw_numbers:
            for operation in operations:
                compare({"op": "eval", "program": node("l", l="number", v=parsed_integer(raw.encode()), t=operation)})
            quotient = builtin("int_divide", n, node("i", v=3))
            program = node("l", l="number", v=parsed_integer(raw.encode()), t=quotient)
            expected = oracle.request({"op": "eval", "program": program})
            try:
                reply = expected["value"]["tagged"]["value"]["integer"]
                if isinstance(reply, int):
                    same = builtin("equal", unwrap("Ok", quotient), parsed_integer(str(reply).encode()))
                    compare({"op": "eval", "program": node("l", l="number", v=parsed_integer(raw.encode()), t=same)})
            except KeyError:
                pass
        # Gleam's structural equality recognizes the same boxed Integer object
        # before inspecting its NaN payload. Copies of one bound value therefore
        # differ from two independently computed NaN Integer objects.
        infinity = node("v", l="infinity")
        nan = node("v", l="nan")
        make_nan = unwrap("Ok", builtin("int_divide", infinity, infinity))
        nan_cases = [builtin("equal", nan, nan), builtin("equal", call(node("c"), nan, node("ta")), call(node("c"), nan, node("ta"))), builtin("equal", nan, make_nan)]
        for operation in nan_cases:
            compare({"op": "eval", "program": node("l", l="infinity", v=parsed_integer(("9" * 400).encode()), t=node("l", l="nan", v=make_nan, t=operation))})
        sources = ["42", "todo", "", "!int_add(20, 22)", "let x = 1 x", "import \"./a.eyg\"", "@standard", "@standard:2", "#!/usr/bin/env eyg\n42", '{"0":"i","v":42}', '{"0":"u"}', "{x: 1, y: [2, 3]}"]
        sources += [generated_source(rng) for _ in range(args.cases)]
        sources += [json.dumps({"0": "i", "v": 1.0}), json.dumps({"0": "@", "p": "demo", "r": -2}), json.dumps({"0": "x", "v": {"/": {"bytes": "AR=="}}})]
        for source in sources:
            compare({"label": "EYGParse", "lift": {"string": source}})
        for _ in range(args.cases):
            compare(signing(rng.randbytes(32), rng.randbytes(rng.randrange(513))))
        for length in [0, 1, 31, 33, 64]:
            compare(signing(rng.randbytes(length), b"test"))
        for request in [
            {"label": "DecodeJSON", "lift": {"string": "[]"}},
            {"label": "EYGParse", "lift": {"integer": 1}},
            {"label": "CreateKey", "lift": {"record": {}}},
            {"label": "CreateKey", "lift": {"tagged": {"label": "Other", "value": {"record": {}}}}},
            {"label": "Sign", "lift": {"record": {}}},
            {"label": "Sign", "lift": {"record": {"key": {"integer": 1}, "data": binary(b"test")}}},
        ]:
            compare(request)
        for _ in range(100):
            request = {"label": "CreateKey", "lift": {"tagged": {"label": "Eddsa", "value": {"record": {}}}}}
            generated = native.request(request)
            counts["CreateKey"] += 1
            try:
                key = generated["value"]["tagged"]["value"]["tagged"]["value"]["record"]
                if key["kty"] != {"string": "OKP"} or key["crv"] != {"string": "Ed25519"}:
                    raise ValueError("wrong JWK metadata")
                if len(base64.b64decode(key["d"]["binary"]["/"]["bytes"] + "==")) != 32:
                    raise ValueError("wrong seed length")
                derived = oracle.request({"label": "derive-public-key", "lift": key["d"]})
                if derived != key["x"]:
                    raise ValueError("public key differs from actual oracle's seed import")
                compare(signing(base64.b64decode(key["d"]["binary"]["/"]["bytes"] + "=="), b"generated-key"))
            except (KeyError, ValueError) as error:
                report["failures"].append({"request": request, "got": generated, "error": str(error)})
        report["passed"] = not report["failures"]
    finally:
        native.close()
        oracle.close()
        report["counts"] = dict(counts)
        args.report.parent.mkdir(parents=True, exist_ok=True)
        args.report.write_text(json.dumps(report, indent=2, ensure_ascii=False) + "\n")
    print(json.dumps({key: value for key, value in report.items() if key != "failures"}))
    if report["failures"]:
        print(json.dumps(report["failures"][:3], ensure_ascii=False, indent=2), file=sys.stderr)
    return 0 if report.get("passed") else 1


if __name__ == "__main__":
    sys.exit(main())
