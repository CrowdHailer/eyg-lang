//// Tool orchestration stays in Gleam; plinthx binds native subprocess methods.

import gleam/dict
import gleam/javascript/promise.{type Promise}
import gleam/result
import otel
import plinthx/bun/runtime
import plinthx/bun/streams
import plinthx/bun/subprocess

pub type Output {
  Output(status: Int, stdout: String, stderr: String)
}

pub fn command(
  cmd: List(String),
  cwd: String,
  env: List(#(String, String)),
) -> Promise(Result(Output, String)) {
  let setup = {
    use bun <- result.try(
      runtime.get() |> result.replace_error("Bun is required"),
    )
    let env =
      dict.merge(dict.from_list(otel.environment()), dict.from_list(env))
      |> dict.to_list
    use child <- result.try(subprocess.spawn(
      bun,
      subprocess.Options(cmd, cwd, env, "ignore", "pipe", "pipe"),
    ))
    use stdout <- result.try(
      subprocess.stdout(child) |> result.replace_error("stdout is not piped"),
    )
    use stderr <- result.try(
      subprocess.stderr(child) |> result.replace_error("stderr is not piped"),
    )
    Ok(#(bun, child, stdout, stderr))
  }
  case setup {
    Error(reason) -> promise.resolve(Error(reason))
    Ok(#(bun, child, stdout, stderr)) -> {
      let out = streams.to_text(bun, stdout)
      let err = streams.to_text(bun, stderr)
      use status <- promise.await(subprocess.exited(child))
      use stdout <- promise.await(out)
      use stderr <- promise.map(err)
      use status <- result.try(status)
      use stdout <- result.try(stdout)
      use stderr <- result.map(stderr)
      Output(status, stdout, stderr)
    }
  }
}

pub fn cli(arguments, env) {
  let binary = otel.env_value(otel.environment(), "EYG_BIN", "")
  let invocation = case binary {
    "" -> [
      "gleam",
      "run",
      "--no-print-progress",
      "--runtime",
      "bun",
      "--",
      ..arguments
    ]
    binary -> [binary, ..arguments]
  }
  command(invocation, "../gleam_cli", env)
}
