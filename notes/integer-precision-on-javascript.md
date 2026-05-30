---
name: Integer precision on JavaScript
description: Numbers on JavaScript are float which limits integer precision.
date: 2026-05-29
---

The EYG source is saved as DAG-JSON, the native JSON.parse implementation uses double-precision floating-point numbers.
Numbers outside the safe range (±2^53−1) will be silently rounded.
EYG uses tha mathematical concept of integers.
EYG does not accept silent failures.

The JavaScript interpreter uses the standard number type for performance.
Whenever a number falls outside the safe range the program, or parser, raises the error.

The [DAG-JSON spec](https://ipld.io/specs/codecs/dag-json/spec/#numbers) clarifies that an integer of any size IS SUPPORTED, only the decoder may not support it. 
For that reason it is correct to encode large integers as numbers in the JSON source files.
Hash values should be calculated from this format too.

This issue introduced the `Unrepresentable` break type. It contains enough information for the program state to be serialized and moved to another runtime that does support the integers.

The erlang runtime uses BigInts by default and so does not have this problem.
Using BigInts on JavaScript is possible but potentially bad for performance.