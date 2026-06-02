---
name: Opaque crypto keys
description: The current effects for creating keys and signing expose key material
date: 2026-06-02
---

The CLI currently implements two cryptographic effects:

- `CreateKey(Eddsa({}))` generates an Ed25519 key pair.
- `Sign({key, data})` signs binary data with key material in the shape returned
  by `CreateKey`.

These effects exist because key generation and signing need host runtime
support.
The current design returns exported key material inside `Eddsa`:

```eyg
Eddsa({kty, crv, x, d})
```

The field names are consistent with JWK field names and the WebCrypto standard.
It provides at least a standard and makes extension easier.

## Exported Keys vs Opaque Handles

The current setup is easy to use.
The downside is the runtime cannot prevent the script from copying secret material.

An opaque design would return key handles instead.
That would protect non-extractable keys, hardware-backed keys, and OS keystore keys.

However opaque handles would have to be a value that could be serialized, all EYG values can be serialized.
Using the public key fingerprint would allow them to be serialized but not conflict if serialized and sent bettween execution contexts.