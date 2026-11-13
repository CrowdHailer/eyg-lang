//// Node process: https://nodejs.org/api/process.html

import gleam/javascript/array.{type Array}
import plinthx/node/stream.{type Stream}

pub type Process

@external(javascript, "./process_ffi.mjs", "get")
pub fn get() -> Result(Process, Nil)

@external(javascript, "./process_ffi.mjs", "env")
pub fn env(process: Process) -> List(#(String, String))

@external(javascript, "./process_ffi.mjs", "heapBytes")
pub fn heap_bytes(process: Process) -> Int

@external(javascript, "./process_ffi.mjs", "stdin")
pub fn stdin(process: Process) -> Stream

@external(javascript, "./process_ffi.mjs", "argv")
pub fn argv(process: Process) -> Array(String)

@external(javascript, "./process_ffi.mjs", "cwd")
pub fn cwd(process: Process) -> Result(String, String)

@external(javascript, "./process_ffi.mjs", "onceExit")
pub fn once_exit(
  process: Process,
  callback: fn(Int) -> Nil,
) -> Result(Process, String)

@external(javascript, "./process_ffi.mjs", "removeExitListener")
pub fn remove_exit_listener(
  process: Process,
  callback: fn(Int) -> Nil,
) -> Result(Process, String)

@external(javascript, "./process_ffi.mjs", "exit")
pub fn exit(process: Process, code: Int) -> Nil

@external(javascript, "./process_ffi.mjs", "onSignal")
pub fn on_signal(
  process: Process,
  signal: String,
  callback: fn() -> Nil,
) -> Result(Process, String)

@external(javascript, "./process_ffi.mjs", "removeSignalListener")
pub fn remove_signal_listener(
  process: Process,
  signal: String,
  callback: fn() -> Nil,
) -> Result(Process, String)

@external(javascript, "./process_ffi.mjs", "setExitCode")
pub fn set_exit_code(process: Process, code: Int) -> Nil

@external(javascript, "./process_ffi.mjs", "signalSelf")
pub fn signal_self(process: Process, signal: String) -> Result(Nil, String)
