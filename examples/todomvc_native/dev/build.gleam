import example_tools as site
import gleam/io
import gleam/javascript/promise
import simplifile

pub fn main() {
  use result <- promise.map(site.build(
    "build/dev/javascript/todomvc_native/native/start.mjs",
    "dist/app.mjs",
  ))
  let assert Ok(_) = result
  let assert Ok(_) =
    simplifile.write(
      "dist/serve.mjs",
      "import { main } from '../build/dev/javascript/todomvc_native/dev.mjs';\nawait main();\n",
    )
  io.println("Built dist/app.mjs")
}
