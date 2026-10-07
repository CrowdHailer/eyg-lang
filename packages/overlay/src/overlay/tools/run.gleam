//// The main tool available to an Overlay agent.
//// Behaviour matches the run CLI command, top level effects are executed.

import castor
import gleam/dict.{type Dict}
import gleam/dynamic/decode
import oas/generator/utils
import overlay/llm/tool

pub const name: String = "run"

pub const description: String =
  "Run an EYG program with top-level effects, including filesystem effects to read and write source files.
Returns the final value, StandardOut/StandardError output, and errors.
Each tool call has a fresh local scope containing only variable `context`."

pub fn parameters() -> List(#(String, castor.Ref(castor.Schema), Bool)) {
  [castor.field("code", castor.string())]
}

pub fn spec() -> tool.Tool {
  tool.Tool(name, description, parameters())
}

pub fn cast(
  arguments: Dict(String, utils.Any),
) -> Result(String, List(decode.DecodeError)) {
  let arguments = utils.fields_to_dynamic(arguments)
  let decoder = {
    decode.field("code", decode.string, decode.success)
  }
  decode.run(arguments, decoder)
}
