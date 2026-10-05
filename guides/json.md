---
name: json
description: Encode, decode and parse JSON strings with EYG.
---

EYG is a strongly typed language.
When decoding JSON it MUST also be passed into a useful datastructure.
The `@json` package is for decoding and encoding JSON.

`parse` performs the `DecodeJSON` effect.

## Parsing simple values

```eyg
let {parse: parse, decode: decode} = @json
let result = parse("true", decode.boolean)
// Will return Ok(True({}))
let result = parse("3", decode.integer)
// Will return Ok(3)
let result = parse("\"hi\"", decode.string)
// Will return Ok("hi")
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
parse("{\"foo\": 3}", decoder)
// will return Ok({foo: 3})
```

## Handling errors

The json library returns string errors.

```eyg
let {parse: parse, decode: decode} = @json
let result = parse("[]", decode.boolean)
// Will return Error("not a boolean")
```


## Encoding

`encode` builds a JSON string from EYG values.
Each encoder returns a `String`, compose them for nested documents.

```eyg
let {encode} = @json
encode.object([
  encode.field("name", encode.string("Ada")),
  encode.field("tags", encode.array([encode.string("admin")])),
  encode.field("age", encode.integer(36)),
  encode.field("active", encode.boolean(True({}))),
  encode.field("manager", encode.null({}))
])
// will return "{\"name\":\"Ada\",\"tags\":[\"admin\"],\"age\":36,\"active\":true,\"manager\":null}"
```
