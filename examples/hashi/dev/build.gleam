import example_tools as site
import gleam/io
import gleam/javascript/promise
import simplifile

pub fn main() {
  use built <- promise.map(site.build(
    "build/dev/javascript/hashi/hashi/start.mjs",
    "dist/app.mjs",
  ))
  let assert Ok(_) = built
  let assert Ok(_) =
    simplifile.write(
      "dist/serve.mjs",
      "import { main } from '../build/dev/javascript/hashi/dev.mjs';\nawait main();\n",
    )
  io.println("Built dist/app.mjs")
}
