import gleam/dynamic.{Dynamic}
import gleam/json.{Json}

external type Worker

external fn start_worker(String) -> Worker =
  "../../browser_ffi.js" "startWorker"

external fn post_message(Worker, Json) -> Nil =
  "../../browser_ffi.js" "postMessage"

external fn on_message(Worker, fn(Dynamic) -> Nil) -> Nil =
  "../../browser_ffi.js" "onMessage"
