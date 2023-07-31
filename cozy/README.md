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