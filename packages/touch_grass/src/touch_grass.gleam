import eyg/interpreter/cast
import gleam/http/request.{type Request}
import gleam/uri
import touch_grass/abort
import touch_grass/copy
import touch_grass/cryptography/create_key
import touch_grass/cryptography/hash
import touch_grass/cryptography/sign
import touch_grass/decode_json
import touch_grass/download
import touch_grass/env
import touch_grass/exit
import touch_grass/eyg_parse
import touch_grass/fetch
import touch_grass/file_system/append_file
import touch_grass/file_system/cwd
import touch_grass/file_system/delete_file
import touch_grass/file_system/make_directory
import touch_grass/file_system/read_directory
import touch_grass/file_system/read_file
import touch_grass/file_system/write_file
import touch_grass/flip
import touch_grass/interface.{type Interface, Interface}
import touch_grass/now
import touch_grass/paste
import touch_grass/print
import touch_grass/prompt
import touch_grass/random
import touch_grass/sleep
import touch_grass/standard_error
import touch_grass/standard_in
import touch_grass/standard_out
import touch_grass/visit

pub fn abort() -> Interface(String, a) {
  Interface(abort.label, abort.lift(), abort.lower(), abort.decode)
}

/// alert is the same interface as Print but show to the user in a browser context
pub fn alert() -> Interface(String, a) {
  Interface("Alert", print.lift(), print.lower(), print.decode)
}

pub fn append_file() -> Interface(append_file.Input, a) {
  Interface(
    append_file.label,
    append_file.lift(),
    append_file.lower(),
    append_file.decode,
  )
}

pub fn copy() -> Interface(String, a) {
  Interface(copy.label, copy.lift(), copy.lower(), copy.decode)
}

pub fn create_key() -> Interface(create_key.Algorithm, a) {
  Interface(
    create_key.label,
    create_key.lift(),
    create_key.lower(),
    create_key.decode,
  )
}

pub fn cwd() -> Interface(Nil, a) {
  Interface(cwd.label, cwd.lift(), cwd.lower(), cwd.decode)
}

pub fn decode_json() -> Interface(BitArray, a) {
  Interface(
    decode_json.label,
    decode_json.lift(),
    decode_json.lower(),
    decode_json.decode,
  )
}

pub fn delete_file() -> Interface(String, a) {
  Interface(
    delete_file.label,
    delete_file.lift(),
    delete_file.lower(),
    delete_file.decode,
  )
}

pub fn download() -> Interface(download.Input, a) {
  Interface(download.label, download.lift(), download.lower(), download.decode)
}

pub fn env() -> Interface(String, a) {
  Interface(env.label, env.lift(), env.lower(), env.decode)
}

pub fn exit() -> Interface(Int, a) {
  Interface(exit.label, exit.lift(), exit.lower(), exit.decode)
}

pub fn eyg_parse() -> Interface(String, a) {
  Interface(
    eyg_parse.label,
    eyg_parse.lift(),
    eyg_parse.lower(),
    eyg_parse.decode,
  )
}

pub fn fetch() -> Interface(Request(BitArray), a) {
  Interface(fetch.label, fetch.lift(), fetch.lower(), fetch.decode)
}

pub fn flip() -> Interface(Nil, a) {
  Interface(flip.label, flip.lift(), flip.lower(), flip.decode)
}

pub fn hash() -> Interface(hash.Input, a) {
  Interface(hash.label, hash.lift(), hash.lower(), hash.decode)
}

pub fn make_directory() -> Interface(String, a) {
  Interface(
    make_directory.label,
    make_directory.lift(),
    make_directory.lower(),
    make_directory.decode,
  )
}

pub fn now() -> Interface(Nil, a) {
  Interface(now.label, now.lift(), now.lower(), now.decode)
}

pub fn paste() -> Interface(Nil, a) {
  Interface(paste.label, paste.lift(), paste.lower(), paste.decode)
}

pub fn print() -> Interface(String, a) {
  Interface(print.label, print.lift(), print.lower(), print.decode)
}

pub fn prompt() -> Interface(String, a) {
  Interface(prompt.label, prompt.lift(), prompt.lower(), prompt.decode)
}

pub fn random() -> Interface(Int, a) {
  Interface(random.label, random.lift(), random.lower(), random.decode)
}

pub fn read_directory() -> Interface(String, a) {
  Interface(
    read_directory.label,
    read_directory.lift(),
    read_directory.lower(),
    read_directory.decode,
  )
}

pub fn read_file() -> Interface(read_file.Input, a) {
  Interface(
    read_file.label,
    read_file.lift(),
    read_file.lower(),
    read_file.decode,
  )
}

pub fn sign() -> Interface(sign.Request, a) {
  Interface(sign.label, sign.lift(), sign.lower(), sign.decode)
}

pub fn sleep() -> Interface(Int, a) {
  Interface(sleep.label, sleep.lift(), sleep.lower(), sleep.decode)
}

pub fn standard_error() -> Interface(String, a) {
  Interface(
    standard_error.label,
    standard_error.lift(),
    standard_error.lower(),
    standard_error.decode,
  )
}

pub fn standard_in() -> Interface(Nil, a) {
  Interface(
    standard_in.label,
    standard_in.lift(),
    standard_in.lower(),
    standard_in.decode,
  )
}

pub fn standard_out() -> Interface(String, a) {
  Interface(
    standard_out.label,
    standard_out.lift(),
    standard_out.lower(),
    standard_out.decode,
  )
}

pub fn visit() -> Interface(uri.Uri, a) {
  Interface(visit.label, visit.lift(), visit.lower(), visit.decode)
}

pub fn write_file() -> Interface(write_file.Input, a) {
  Interface(
    write_file.label,
    write_file.lift(),
    write_file.lower(),
    write_file.decode,
  )
}

pub fn map(interface: Interface(t, a), f: fn(t) -> u) -> Interface(u, a) {
  let Interface(decode:, ..) = interface
  let decode = cast.map(decode, f)
  Interface(..interface, decode:)
}

pub fn replace(interface: Interface(Nil, a), value: u) -> Interface(u, a) {
  let Interface(decode:, ..) = interface
  let decode = cast.map(decode, fn(_: Nil) { value })
  Interface(..interface, decode:)
}
