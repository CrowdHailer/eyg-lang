# json

JSON parsing and encoding.

## Decoding

```eyg
let json = import "../json/index.eyg"
match json.parse("{\"name\":\"Ada\"}", json.decode.object(
  json.decode.field("name", json.decode.string)
)) {
  Ok(name) -> { name }
  Error(reason) -> { reason }
}
```

| Decoder                       | Decodes to                                  |
|-------------------------------|---------------------------------------------|
| `decode.boolean`              | `True({}) \| False({})`                     |
| `decode.integer`              | `Int`                                        |
| `decode.string`               | `String`                                     |
| `decode.list(item_decoder)`   | `List(a)`                                    |
| `decode.field(label, dec)`    | the field's decoded value (aborts if missing) |
| `decode.object(decoder_fn)`   | wraps a fields-record builder                 |

`parse(json, decoder)` returns `Ok(value) | Error(reason)`.
`parse_bytes(binary, decoder)` is the same for `Binary` input.
`expect(result, msg)` aborts with `msg` on `Error`.

## Encoding

```eyg
let json = import "../json/index.eyg"
let e = json.encode

let payload = e.object([
  e.field("name", e.string("Ada")),
  e.field("age", e.integer(36)),
])
// -> "{\"name\":\"Ada\",\"age\":36}"
```

| Encoder              | Produces                       |
|----------------------|--------------------------------|
| `encode.string(s)`   | `"\"<escaped>\""`              |
| `encode.integer(n)`  | `"<n>"`                         |
| `encode.boolean(b)`  | `"true"` / `"false"`            |
| `encode.null(_)`     | `"null"`                        |
| `encode.array(items)`| `"[a,b,...]"` over encoded strings |
| `encode.object(fields)`| `"{\"k\":v,...}"`            |
| `encode.field(k, v)` | `{key, value}` helper for `object` |
