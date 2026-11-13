//// Install the dispatcher bundle and verified native glue into a source checkout.

import argv
import filepath
import gleam/io
import gleam/list
import opencode_plugin/integration
import simplifile

pub fn main() {
  let assert [checkout] = argv.load().arguments
  let source = filepath.join(checkout, "packages/opencode/src/session/tools.ts")
  let assert Ok(code) = simplifile.read(source)
  let patched = case integration.patch(code) {
    Ok(patched) -> patched
    Error(reason) -> panic as reason
  }
  let files = ["dispatch.mjs"]
  // Read all assets and validate the source before changing the checkout.
  let assets =
    list.map(files, fn(file) {
      let assert Ok(bytes) = simplifile.read_bits("dist/" <> file)
      #(file, bytes)
    })
  let target = filepath.join(checkout, "packages/opencode/src/tool/eyg")
  let assert Ok(_) = simplifile.create_directory_all(target)
  list.each(assets, fn(asset) {
    let assert Ok(_) =
      simplifile.write_bits(filepath.join(target, asset.0), asset.1)
    Nil
  })
  let assert Ok(_) =
    simplifile.write(
      target <> "/dispatch.d.mts",
      "export function wrap_tools(tools: any, input: any, parent: (id: string) => Promise<any>): Promise<any>;\nexport function notify(options: any, value: any): void;\nexport function outer_args(options: any, fallback: any): any;\n",
    )
  let assert Ok(_) = simplifile.write(source, patched)
  io.println(
    "Installed Gleam dispatcher into OpenCode v" <> integration.version,
  )
}
