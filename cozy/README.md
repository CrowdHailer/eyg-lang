# Cozy

Uses [CozoDB](https://github.com/cozodb/cozo) for graph queries

```
npm i -g rollup sirv

(cd eyg; gleam run cli cozo ./saved/saved.json)
cp wisdom/tmp.db.json cozy/build/db.json

(cd cozy;
  rollup --config rollup.config.mjs && \
  cp index.html build/index.html && \
  cp node_modules/cozo-lib-wasm/cozo_lib_wasm_bg.wasm build && \
  
  npx sirv ./build --dev --host 0.0.0.0 --port 5000
)
```

https://github.com/Xe/x/blob/master/conferences/gceu23/cmd/aiyou/main.go#L16
https://www.youtube.com/watch?v=QNDvfez6QL0&list=PLtoVuM73AmsJWvXYd_9rbYXcbv1UdzeLT&index=2
https://github.com/tetratelabs/wazero/blob/main/examples/basic/add.go
https://www.secondstate.io/articles/extend-golang-app-with-webassembly-rust/
https://eli.thegreenplace.net/2023/faas-in-go-with-wasm-wasi-and-rust/

There are a bunch of issues in building, mayebe rust version 1.72 doesn't build cozo