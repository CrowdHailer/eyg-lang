import gleam/javascript/array.{Array}

@external(javascript, "../plinth_ffi.js", "argv")
fn do_args(a: Int) -> Array(String)

/// Returns a list containing the command-line arguments passed when the Node.js process was launched.
/// The first element will be `process.execPath`.
/// The second element will be the path to the JavaScript file being executed.
/// The remaining elements will be any additional command-line arguments.
pub fn args() {
  array.to_list(do_args(0))
}

/// Returns the current working directory of the Node.js process.
@external(javascript, "process", "cwd")
pub fn cwd() -> String

/// instructs Node.js to terminate the process synchronously with an exit status of `code`.
/// Node.js will not terminate until all the `exit` event listeners are called.
@external(javascript, "process", "exit")
pub fn exit(code code: Int) -> Nil

pub type HRTime

@external(javascript, "process", "hrtime")
pub fn start() -> HRTime

@external(javascript, "process", "hrtime")
pub fn duration(a: HRTime) -> #(Int, Int)
