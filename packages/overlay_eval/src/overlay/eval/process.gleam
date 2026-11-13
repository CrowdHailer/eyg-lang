import gleam/io
import plinthx/node/process

pub fn fail(message: String) -> Nil {
  io.println_error(message)
  exit_code(1)
}

/// Set the code the process exits with, once the eval has finished.
pub fn exit_code(code: Int) -> Nil {
  case process.get() {
    Ok(process) -> process.set_exit_code(process, code)
    Error(Nil) -> Nil
  }
}
