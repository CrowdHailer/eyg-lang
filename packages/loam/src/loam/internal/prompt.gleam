//// Consume exactly one input line, leaving later bytes for subsequent effects.

import gleam/bit_array
import gleam/io
import gleam/javascript/promise
import gleam/list
import gleam/result
import gleam/string
import plinthx/node/fs

pub fn read_line(text) {
  io.print(text)
  read([])
}

fn read(bytes) {
  use byte <- promise.await(fs.read(0, 1))
  case byte {
    Ok(<<"\n">>) -> promise.resolve(decode(bytes))
    Ok(<<>>) | Error("EOF") ->
      case bytes {
        [] -> promise.resolve(Error(Nil))
        _ -> promise.resolve(decode(bytes))
      }
    Ok(byte) -> read([byte, ..bytes])
    Error("EAGAIN") | Error("EINTR") -> {
      use _ <- promise.await(promise.wait(10))
      read(bytes)
    }
    Error(_) -> promise.resolve(Error(Nil))
  }
}

fn decode(bytes) {
  use text <- result.try(
    bit_array.concat(list.reverse(bytes))
    |> bit_array.to_string
    |> result.replace_error(Nil),
  )
  Ok(case string.ends_with(text, "\r") {
    True -> string.drop_end(text, 1)
    False -> text
  })
}
