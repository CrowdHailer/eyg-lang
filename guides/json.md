---
name: json
description: Decode and parse JSON strings with EYG.
---

EYG is a strongly typed language.
When decoding JSON it MUST also be passed into a useful datastructure.
The `@json` package is for decoding JSON.

## Parsing simple values

```eyg
let {parse: parse, decode: decode} = @json
let result = parse("true", decode.boolean)
// Will return Ok(True({}))
let result = parse("3", decode.integer)
// Will return Ok(3)
let result = parse("\"hi\"", decode.string)
// Will return Ok("hi)
```

EYG does not support parsing floats

## Parsing lists
```eyg
let {parse: parse, decode: decode} = @json
let decoder = decode.list(decode.integer)
let result = parse("[1, 2, 3]", decoder)
// Will return Ok([1, 2, 3])
```

## Parsing objects
```eyg
let {parse: parse, decode: decode} = @json
let decoder = decode.object((decoded) -> {
  let foo = decode.field("foo", decode.integer, decoded)
  {foo: foo}
})
parse("{"foo": 3}", decoder),
// will return Ok({foo: 3})
```

## Handling errors
The json library returns string errors.
```eyg
let {parse: parse, decode: decode} = @json
let result = parse("[]", decode.boolean)
// Will return Error("not a boolean")
```

The @json package includes the `expect` function for aborting on error.
Use this when making quick scripts

```eyg
let {parse: parse, decode: decode, expect: expect} = @json
let result = expect(parse("true", decode.boolean), "failed to decode")
// Will return Error("not a boolean")
```
