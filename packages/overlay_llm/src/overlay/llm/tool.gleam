import castor
import gleam/dynamic/decode
import oas/generator/utils

pub type Tool {
  Tool(
    name: String,
    description: String,
    parameters: List(#(String, castor.Ref(castor.Schema), Bool)),
  )
}

pub type Call {
  Call(id: String, function: FunctionCall)
}

pub type FunctionCall {
  FunctionCall(name: String, arguments: utils.Fields)
}

pub type Return {
  Return(text: String, images: List(String))
}

pub type ToolCallFailure {
  UnknownTool(name: String)
  BadArguments(errors: List(decode.DecodeError))
  ExecutionAborted(reason: String)
}

pub fn tool_call_failure_to_string(failure) {
  case failure {
    UnknownTool(name:) -> "Unknown tool: " <> name
    BadArguments(errors: _) -> "Bad arguments for tool call "
    ExecutionAborted(reason:) -> "Execution aborted: " <> reason
  }
}
