---
name: Preserve JSON documents
description: Change an existing string field while retaining unknown JSON fields, values and their order.
---

# Preserve JSON documents

`json.document` keeps the ordered representation returned by `DecodeJSON`.
Replacing one string retains other fields, nested arrays/objects, nulls,
booleans and exact decimal/exponent numbers. Whitespace is normalized.

From the repository root:

```sh
eyg run -c 'let document = import "./eyg_packages/json/document.eyg"
let parsed = match document.parse("{\"tokens\":{\"access\":\"old\",\"extra\":true},\"keep\":[1,null]}") {
  Ok(value) -> { value }
  Error(reason) -> { !never(perform Abort(reason)) }
}
let changed = match document.replace(parsed, ["tokens", "access"], "new") {
  Ok(value) -> { value }
  Error(reason) -> { !never(perform Abort(reason)) }
}
perform StandardOut(document.render(changed))'
```

The result is `{"tokens":{"access":"new","extra":true},"keep":[1,null]}`.
`replace` returns an error for missing fields, non-object intermediate values
or non-string targets. An empty path replaces a string root. It changes the
first matching field at each level and leaves the input immutable.

`parse` uses the existing `DecodeJSON` effect. `replace` is pure; `render`
accepts the document representation produced by `parse` and aborts on invalid
representations. Run `eyg script entry.eyg` to check the complete package suite.
