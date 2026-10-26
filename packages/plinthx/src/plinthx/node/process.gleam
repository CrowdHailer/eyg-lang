//// Node process: https://nodejs.org/api/process.html

pub type Process

@external(javascript, "./process_ffi.mjs", "get")
pub fn get() -> Result(Process, Nil)

@external(javascript, "./process_ffi.mjs", "env")
pub fn env(process: Process) -> List(#(String, String))
