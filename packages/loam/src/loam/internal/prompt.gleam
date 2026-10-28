//// Consume exactly one input line, leaving later bytes for subsequent effects.

import gleam/bit_array
import gleam/io
import gleam/javascript/promise
import gleam/list
import gleam/option.{None, Some}
import gleam/order
import gleam/result
import gleam/string
import javascript/mutable_reference as cell
import loam/internal/key_decoder as decoder
import loam/internal/prompt_editor as editor
import plinthx/javascript/promise as native_promise
import plinthx/node/fs
import plinthx/node/process
import plinthx/node/tty

pub opaque type History {
  History(cell.MutableReference(List(String)))
}

pub fn new() {
  History(cell.new([]))
}

pub fn read_line(text, history: History) {
  io.print(text)
  let History(ref) = history
  let input = case process.get() {
    Ok(host) -> Some(process.stdin(host))
    Error(_) -> None
  }
  let result = case input {
    Some(input) ->
      case tty.is_tty(input) {
        Ok(True) -> edit(input, cell.get(ref))
        _ -> read([])
      }
    None -> read([])
  }
  use result <- promise.map(result)
  case result {
    Ok("") | Error(_) -> Nil
    Ok(line) -> {
      let _ = cell.update(ref, fn(history) { [line, ..history] })
      Nil
    }
  }
  result
}

fn edit(input, history) {
  let assert Ok(_) = tty.set_stream_raw_mode(input, True)
  io.print("\u{1b}7")
  let checked =
    edit_loop(editor.new(history), decoder.new())
    |> promise.map(Ok)
    |> promise.rescue(Error)
  use checked <- promise.await(checked)
  let _ = tty.set_stream_raw_mode(input, False)
  io.print("\n")
  case checked {
    Ok(result) -> promise.resolve(result)
    Error(reason) -> {
      let assert Ok(constructor) = native_promise.get()
      native_promise.reject(constructor, reason)
    }
  }
}

fn edit_loop(model: editor.Model, decoder) {
  use keys <- promise.await(next_keys(decoder, 0))
  case keys {
    Error(_) -> promise.resolve(Error(Nil))
    Ok(#(decoder, keys)) ->
      case apply_keys(model, keys) {
        editor.Submit(line) -> promise.resolve(Ok(line))
        editor.Stop -> promise.resolve(Error(Nil))
        editor.Continue(model) -> edit_loop(model, decoder)
      }
  }
}

fn apply_keys(model: editor.Model, keys) {
  case keys {
    [] -> editor.Continue(model)
    [decoder.Interrupt, ..] -> editor.Stop
    [decoder.Key(key), ..rest] ->
      case editor.update(model, key) {
        editor.Continue(next) -> {
          case next.line == model.line {
            True -> Nil
            False ->
              case
                model.line.after == []
                && next.line.after == []
                && string.length(key) == 1
                && string.compare(key, " ") != order.Lt
              {
                True -> io.print(key <> "\u{1b}[0J")
                False -> io.print(editor.redraw(next.line))
              }
          }
          apply_keys(next, rest)
        }
        done -> done
      }
  }
}

fn next_keys(decoder: decoder.Decoder, idle) {
  use byte <- promise.await(fs.read(0, 1))
  case byte {
    Ok(<<>>) | Error("EOF") -> promise.resolve(Error(Nil))
    Error("EAGAIN") | Error("EINTR") -> {
      case decoder.buffer != "" && idle >= 20 {
        True -> promise.resolve(Ok(decoder.flush(decoder)))
        False -> {
          use _ <- promise.await(promise.wait(10))
          next_keys(decoder, idle + 10)
        }
      }
    }
    Error(_) -> promise.resolve(Error(Nil))
    Ok(byte) -> {
      let assert <<lead:8>> = byte
      let trailing = case lead {
        _ if lead >= 240 -> 3
        _ if lead >= 224 -> 2
        _ if lead >= 192 -> 1
        _ -> 0
      }
      use text <- promise.await(character(<<lead>>, trailing))
      case text {
        Error(_) -> promise.resolve(Error(Nil))
        Ok(text) -> {
          let #(decoder, events) = decoder.feed(decoder, text)
          case events {
            [] -> next_keys(decoder, 0)
            _ -> promise.resolve(Ok(#(decoder, events)))
          }
        }
      }
    }
  }
}

fn character(bytes, trailing) {
  case trailing {
    0 -> promise.resolve(bit_array.to_string(bytes))
    _ -> {
      use byte <- promise.await(fs.read(0, 1))
      case byte {
        Ok(<<>>) -> promise.resolve(Error(Nil))
        Ok(byte) -> character(<<bytes:bits, byte:bits>>, trailing - 1)
        Error("EAGAIN") | Error("EINTR") -> {
          use _ <- promise.await(promise.wait(10))
          character(bytes, trailing)
        }
        _ -> promise.resolve(Error(Nil))
      }
    }
  }
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
