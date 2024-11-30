import eyg/hub/archive
import eygir/decode
import gleam/dynamic
import gleam/http
import gleam/http/request
import gleam/http/response
import gleam/int
import gleam/io
import gleam/json
import javascript/mutable_reference as ref

// ResultServerError
// server in memory /state

pub fn do_handle(request, archive) {
  let segments = request.path_segments(request)
  case request.method, segments {
    http.Post, [series, next] -> {
      let decoder = dynamic.field("source", decode.decoder)
      let assert Ok(next) = int.parse(next)
      let assert Ok(source) = json.decode_bits(request.body, decoder)
      case archive.publish(archive, series, next, source, Nil) {
        Ok(archive) -> {
          #(response.new(201) |> response.set_body(<<>>), archive)
        }
        Error(_) -> todo as "error"
      }
    }
    _, _ -> {
      io.debug(#(request.method, segments))
      todo as "not supported"
    }
  }
}

pub fn handle(request, state) {
  let archive = ref.get(state)
  let #(response, archive) = do_handle(request, archive)
  ref.set(state, archive)
  response
}
