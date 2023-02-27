import gleam/javascript/array.{Array}

external fn do_args(Int) -> Array(String) =
  "" "process.argv.slice"

/// Returns a list containing the command-line arguments passed when the Node.js process was launched. 
/// The first element will be `process.execPath`. 
/// The second element will be the path to the JavaScript file being executed. 
/// The remaining elements will be any additional command-line arguments.
pub fn args() {
  array.to_list(do_args(0))
}

/// Returns the current working directory of the Node.js process.
pub external fn cwd() -> String =
  "" "process.cwd"

/// instructs Node.js to terminate the process synchronously with an exit status of `code`.
/// Node.js will not terminate until all the `exit` event listeners are called.
pub external fn exit(code: Int) -> Nil =
  "" "process.exit"
