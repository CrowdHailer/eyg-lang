# Portable SHA-256

`sha256.hash(bytes)` and `sha256.hmac(key, message)` return a 32-byte digest.
The implementation uses Gleam arithmetic without host bindings, so synchronous
callers work on the BEAM and in browsers, Node and Bun. Glasshouse keeps its
existing `glasshouse/sha256.hash` entry point.

Checks cover known digests, padding boundaries, RFC 4231 HMAC vectors and
comparison with the host cryptography library on both targets:

```sh
gleam test
gleam test --target javascript --runtime bun
```
