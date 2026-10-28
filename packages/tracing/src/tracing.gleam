import argv
import gleam/int
import gleam/io
import gleam/javascript/promise
import gleam/result
import otel
import plinthx/bun/server
import tracing/capture
import tracing/demo
import tracing/export
import tracing/render

pub fn main() {
  case argv.load().arguments {
    ["demo-server"] -> {
      let port =
        otel.env_value(otel.environment(), "EYG_DEMO_PORT", "8787")
        |> int.parse
        |> result.unwrap(8787)
      let assert Ok(demo) = demo.start(port)
      io.println(
        "EYG tracing fixtures: http://127.0.0.1:"
        <> int.to_string(server.port(demo.server)),
      )
      promise.resolve(Ok(Nil))
    }
    ["capture"] -> capture.run(False, "presentation")
    ["capture", output] -> capture.run(False, output)
    ["profile-capture"] -> capture.run(True, "presentation")
    ["profile-capture", output] -> capture.run(True, output)
    ["render"] -> render.run("presentation", "presentation")
    ["render", input, output] -> render.run(input, output)
    ["export"] -> export.run("presentation")
    ["export", directory] -> export.run(directory)
    _ ->
      promise.resolve(Error(
        "usage: gleam run -- demo-server | capture [output] | profile-capture [output] | render [input output] | export [directory]",
      ))
  }
  |> promise.map(fn(result) {
    let assert Ok(_) = result
    Nil
  })
}
