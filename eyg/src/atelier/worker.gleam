import gleam/io
import eygir/decode
import eyg/runtime/standard

pub fn infer(data) {
  io.debug(Ok("foo111111111111"))
  // io.debug()
  case decode.decoder(data) {
    Ok(source) -> standard.infer(source)
    Error(_) -> todo("need to not send")
  }
}
