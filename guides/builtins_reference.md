---
title: Builtins reference
description: Refernce of every builtin function defined.
---

Builtins are runtime-provided functionality.
They used in scripts with the syntax `!name`.

Builtins have the same behaviour over all EYG implementations.
A runtime agnostic test suite for builtins is [available](../spec/evaluation/builtins_suite.json).

For behaviour that varies between runtime use effect.

Conventions:

- `{}` is the unit record.
- Fallible builtins (e.g. `!string_from_binary`, `!int_parse`) return a `Ok(vale) | Error(reason)`.

## General

| Builtin     | Signature                    | Notes                                                  |
|-------------|------------------------------|--------------------------------------------------------|
| `!equal`    | `(a, a) -> True({}) | False` | Returns `True({})` or `False({})`.                     |
| `!fix`      | `((self, ...) -> ...)`       | Y-combinator. Use for self-recursive closures.         |
| `!fixed`    | `(f, f)`                     | Lower-level fixed-point pair; prefer `!fix`.           |
| `!never`    | `(Never) -> a`               | Conventionally used with `!never(perform Abort(msg))`.         |

## Integers

| Builtin          | Signature                | Notes                                       |
|------------------|--------------------------|---------------------------------------------|
| `!int_add`       | `(Int, Int) -> Int`      |                                             |
| `!int_subtract`  | `(Int, Int) -> Int`      |                                             |
| `!int_multiply`  | `(Int, Int) -> Int`      |                                             |
| `!int_divide`    | `(Int, Int) -> Ok(Int) \| Error({})`      | Integer division.                           |
| `!int_absolute`  | `(Int) -> Int`           |                                             |
| `!int_compare`   | `(Int, Int) -> Lt({}) \| Eq({}) \| Gt({})`      | |
| `!int_parse`     | `(String) -> Ok(Int) \| Error({})` | Returns `Error({})` on bad input.      |
| `!int_to_string` | `(Int) -> String`        |                                             |

## Strings

| Builtin                 | Signature                                                       | Notes                                                                                  |
|-------------------------|------------------------------------------------------------------|----------------------------------------------------------------------------------------|
| `!string_append`        | `(String, String) -> String`                                     |                                                                                        |
| `!string_length`        | `(String) -> Int`                                                | Length in graphemes.                                                                   |
| `!string_uppercase`     | `(String) -> String`                                             |                                                                                        |
| `!string_lowercase`     | `(String) -> String`                                             |                                                                                        |
| `!string_starts_with`   | `(String, String) -> True({}) \| False({})`                                        |                                                               |
| `!string_ends_with`     | `(String, String) -> True({}) \| False({})`                                        |                                                               |
| `!string_replace`       | `(String, String, String) -> String`                             | `!string_replace(input, from, to)`.                                                    |
| `!string_split`         | `(String, String) -> {head: String, tail: List(String)}`         | Note the record shape: `head` is the first piece, `tail` is the rest as a flat list.   |
| `!string_split_once`    | `(String, String) -> Ok({pre: String, post: String}) \| Error({})`    | Splits on first occurrence; `Error({})` if the separator is absent.                    |
| `!string_to_binary`     | `(String) -> Binary`                                             | UTF-8 encode.                                                                          |
| `!string_from_binary`   | `(Binary) -> Ok(String) \| Error({})`                                 | UTF-8 decode; `Error({})` if the binary isn't valid UTF-8.                             |

## Lists

| Builtin       | Signature                              | Notes                                                                                                 |
|---------------|----------------------------------------|-------------------------------------------------------------------------------------------------------|
| `!list_pop`   | `(List(a)) -> Ok({head: a, tail: List(a)} \| Error({})` | `Error({})` for the empty list.                                                  |
| `!list_fold`  | `(List(a), b, (a, b) -> b) -> b`       | Standard left-fold. Base for all recursive primitives such as map and each                        |

## Binaries

| Builtin                  | Signature                                | Notes                                                                |
|--------------------------|------------------------------------------|----------------------------------------------------------------------|
| `!binary_size`           | `(Binary) -> Int`                        | Size in bytes.                                                       |
| `!binary_concat`         | `(Binary, Binary) -> Binary`             |                                                                      |
| `!binary_from_integers`  | `(List(Int)) -> Binary`                  | Each int must be 0..255.                                             |
| `!binary_fold`           | `(Binary, b, (Int, b) -> b) -> b`        | Byte-by-byte left fold.                                              |

## Common idioms

### Iterate a list for its side effects

There is no dedicated `each` builtin — fold with a discard accumulator:

```eyg
let _ = !list_fold(items, {}, (item, _) -> {
  perform Print(!string_append(item, "\n"))
})
```

### Split a string into a flat list of lines

```eyg
let {head, tail} = !string_split(text, "\n")
let lines = [head, ..tail]
```

