import eyg/interpreter/cast
import gleam/http/request.{type Request}
import gleam/uri
import touch_grass/abort
import touch_grass/copy
import touch_grass/decode_json
import touch_grass/download
import touch_grass/fetch
import touch_grass/flip
import touch_grass/interface.{type Interface, Interface}
import touch_grass/paste
import touch_grass/print
import touch_grass/prompt
import touch_grass/random
import touch_grass/visit

pub fn abort() -> Interface(String, a, b) {
  Interface(abort.label, abort.lift(), abort.lower(), abort.decode)
}

/// alert is the same interface as Print but show to the user in a browser context
pub fn alert() -> Interface(String, a, b) {
  Interface("Alert", print.lift(), print.lower(), print.decode)
}

pub fn copy() -> Interface(String, a, b) {
  Interface(copy.label, copy.lift(), copy.lower(), copy.decode)
}

pub fn decode_json() -> Interface(BitArray, a, b) {
  Interface(
    decode_json.label,
    decode_json.lift(),
    decode_json.lower(),
    decode_json.decode,
  )
}

pub fn download() -> Interface(download.Input, a, b) {
  Interface(download.label, download.lift(), download.lower(), download.decode)
}

pub fn fetch() -> Interface(Request(BitArray), a, b) {
  Interface(fetch.label, fetch.lift(), fetch.lower(), fetch.decode)
}

pub fn flip() -> Interface(Nil, a, b) {
  Interface(flip.label, flip.lift(), flip.lower(), flip.decode)
}

pub fn paste() -> Interface(Nil, a, b) {
  Interface(paste.label, paste.lift(), paste.lower(), paste.decode)
}

pub fn print() -> Interface(String, a, b) {
  Interface(print.label, print.lift(), print.lower(), print.decode)
}

pub fn prompt() -> Interface(String, a, b) {
  Interface(prompt.label, prompt.lift(), prompt.lower(), prompt.decode)
}

pub fn random() -> Interface(Int, a, b) {
  Interface(random.label, random.lift(), random.lower(), random.decode)
}

pub fn visit() -> Interface(uri.Uri, a, b) {
  Interface(visit.label, visit.lift(), visit.lower(), visit.decode)
}

pub fn map(interface: Interface(t, a, b), f: fn(t) -> u) -> Interface(u, a, b) {
  let Interface(decode:, ..) = interface
  let decode = cast.map(decode, f)
  Interface(..interface, decode:)
}

pub fn replace(interface: Interface(Nil, a, b), value: u) -> Interface(u, a, b) {
  let Interface(decode:, ..) = interface
  let decode = cast.map(decode, fn(_: Nil) { value })
  Interface(..interface, decode:)
}
