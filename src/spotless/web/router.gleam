import gleam/atom.{Atom}
import gleam/bit_builder.{BitBuilder}
import gleam/bit_string.{BitString}
import gleam/dynamic.{Dynamic}
import gleam/io
// import gleam/list
// import gleam/option.{None, Some}
import gleam/string
// import gleam/result
// import gleam/uri
import gleam/beam
import gleam/beam/charlist.{Charlist}
import gleam/http.{Get, Options, Request, Response}
// import gleam/httpc
// import gleam/json
// import floki
import perimeter/scrub.{RejectedInput, Report}
// import glance

external fn write_string(filename: String, contents: String) -> Result(Nil, Nil) = "file" "write_file"
external fn cmd(command: Charlist) -> String = "os" "cmd"
external fn recompile() -> Nil ="Elixir.IEx.Helpers" "recompile"
external fn apply(Atom, Atom, List(Dynamic)) -> Dynamic = "erlang" "apply"
    
fn route(request: Request(BitString), config: Nil) {
  io.debug(request)
  case request.method, http.path_segments(request) {
    http.Post, ["save"] -> {
        assert Ok(source) = bit_string.to_string(request.body)
        // file.write_string("src/untrusted_1234.gleam",souce)
        case write_string("src/untrusted/session_1234.gleam", source) {
            Error(_) -> todo("An error")
            // Doesn't match Ok
            _ -> Nil
        }

        cmd(charlist.from_string("gleam compile-package --src src --out gen --name updated"))
        |> io.debug()
        recompile()
                |> io.debug()
        let result = apply(atom.create_from_string("untrusted@session_1234"), atom.create_from_string("inc"), [dynamic.from(2)])
        io.debug(result)
        http.response(200)
        |> http.set_resp_body(bit_builder.from_bit_string(bit_string.from_string(string.concat([beam.format(result), "\r\n"]))))
        |> Ok()
        |> io.debug
        // Return the result of compiling this request.
        // On the page have a button that says run that calls with get.
        // Have various things you can rely on like perimeter
        // have the ability to clone?
        // Need a page that shows dirty or not
    }
    _, _ ->
      http.response(404)
      |> http.set_resp_body(bit_builder.from_bit_string(<<>>))
      |> Ok()
  }
}

pub fn handle(request: Request(BitString), config: Nil) -> Response(BitBuilder) {
  case route(request, config) {
    Ok(response) -> response
    Error(report) -> scrub.to_response(report)
  }
  |> http.prepend_resp_header("access-control-allow-origin", "*")
  |> http.prepend_resp_header("access-control-allow-credentials", "true")
  |> http.prepend_resp_header(
    "access-control-allow-headers",
    "content-type, sentry-trace",
  )
}