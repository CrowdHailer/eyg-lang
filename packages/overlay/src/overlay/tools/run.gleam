//// The main tool available to an Overlay agent.
//// Behaviour matches the run CLI command, top level effects are executed.

import castor
import gleam/dict.{type Dict}
import gleam/dynamic/decode
import oas/generator/utils
import overlay/llm/tool

pub const name: String = "run"

pub const description: String = "Run an EYG program, the program may have effects at a top level."

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
