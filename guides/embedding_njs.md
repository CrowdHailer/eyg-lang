---
name: Compiled EYG in nginx
description: Await native subrequests from an EYG request handler in QuickJS.
---

# Compiled EYG in nginx

[examples/njs](../examples/njs/) compiles handler.eyg to an ES module and runs
it inside nginx's JavaScript module. The Gleam adapter constructs the request,
answers Log and Subrequest, and returns the EYG response through nginx.
GET awaits `/upstream` and includes its body; other methods return 405.

From examples/njs, with Docker, Gleam and Bun installed:

```sh
gleam test
gleam run -m nginx -- check
```

This builds the EYG module and Gleam host, starts the pinned nginx image on
127.0.0.1:8196, checks real GET/POST responses, and stops its container.
The verified image provides nginx 1.29.8 and njs 0.9.6; its digest is in nginx.gleam.
Use `gleam run -m nginx -- start` to leave it running, then visit
http://127.0.0.1:8196/a/b. Stop it with `gleam run -m nginx -- stop`.

The configuration selects `js_engine qjs` for the generated ECMAScript.
nginx documents [engine selection](https://nginx.org/en/docs/http/ngx_http_js_module.html#js_engine)
and the [request API](https://nginx.org/en/docs/njs/reference.html).
Subrequest's native Promise is awaited before resuming EYG. The six-line FFI
only accesses request properties and methods; conversion and callback routing
live in Gleam. The generated entry binds the compiled program to that adapter.

No runtime package fetch occurs: the program has no references and its module
contains the Gleam continuation runtime. `compiler.to_module` refuses remaining
references, so callers must inline them first. nginx owns imported modules and
its JavaScript contexts; no separate EYG hub cache or persistent shell is kept.

Run `gleam run -m nginx -- check` to check the real service: GET 200, POST 405 and cleanup. Unit checks consume the actual compiled module with Gleam request callbacks, including logging, awaited subrequests, method refusal and invalid-program rejection.
