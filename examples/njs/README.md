# Compiled EYG in nginx

The EYG handler logs the request and awaits an nginx subrequest for GET.
Its host adapter and build/service tools are Gleam. Six bindings access the
native nginx request; a generated three-line entry connects the modules.

```sh
gleam test
gleam run -m nginx -- check
```

The check compiles the EYG module, bundles the Gleam adapter, starts a pinned
nginx container on 127.0.0.1:8196, verifies GET/POST and stops it. Docker must
be available. Use `gleam run -m nginx -- start` to keep it running and
`gleam run -m nginx -- stop` when finished.

See the [guide](../../guides/embedding_njs.md) for the effect boundary,
QuickJS configuration and checked recording.
