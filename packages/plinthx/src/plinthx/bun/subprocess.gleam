//// Bun subprocesses: https://bun.sh/docs/api/spawn

import gleam/javascript/promise.{type Promise}
import plinthx/browser/readable_stream.{type ReadableStream}
import plinthx/bun/runtime.{type Bun}

pub type Subprocess

pub type Options {
  Options(
    cmd: List(String),
    cwd: String,
    env: List(#(String, String)),
    stdin: String,
    stdout: String,
    stderr: String,
  )
}

@external(javascript, "./subprocess_ffi.mjs", "spawn")
pub fn spawn(bun: Bun, options: Options) -> Result(Subprocess, String)

@external(javascript, "./subprocess_ffi.mjs", "spawnWithInput")
pub fn spawn_with_input(
  bun: Bun,
  options: Options,
  input: BitArray,
) -> Result(Subprocess, String)

@external(javascript, "./subprocess_ffi.mjs", "exited")
pub fn exited(process: Subprocess) -> Promise(Result(Int, String))

@external(javascript, "./subprocess_ffi.mjs", "stdout")
pub fn stdout(process: Subprocess) -> Result(ReadableStream, Nil)

@external(javascript, "./subprocess_ffi.mjs", "stderr")
pub fn stderr(process: Subprocess) -> Result(ReadableStream, Nil)

@external(javascript, "./subprocess_ffi.mjs", "readableStreamToText")
pub fn readable_stream_to_text(
  bun: Bun,
  stream: ReadableStream,
) -> Promise(Result(String, String))
