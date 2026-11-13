//// Per-run key input ownership. Parsing, queues and cancellation are Gleam.

import gleam/javascript/promise
import gleam/list
import gleam/option.{type Option, None, Some}
import javascript/mutable_reference as cell
import loam/internal/key_decoder as decoder
import plinthx/node/process
import plinthx/node/stream
import plinthx/node/timers
import plinthx/node/tty

type Session {
  Session(
    host: process.Process,
    input: stream.Stream,
    changed: fn(String) -> Nil,
    exited: fn(Int) -> Nil,
  )
}

type Waiter {
  Waiter(id: Int, resolve: fn(Option(String)) -> Nil, timer: timers.Timeout)
}

type State {
  State(
    session: Option(Session),
    decoder: decoder.Decoder,
    queue: List(String),
    waiting: Option(Waiter),
    next: Int,
    escape_timer: Option(timers.Timeout),
  )
}

pub opaque type Reader {
  Reader(cell.MutableReference(State))
}

pub fn new() {
  Reader(cell.new(State(None, decoder.new(), [], None, 0, None)))
}

pub fn release(reader: Reader) {
  let Reader(ref) = reader
  let state = cell.get(ref)
  let _ =
    cell.set(ref, State(None, decoder.new(), [], None, state.next + 1, None))
  case state.waiting {
    Some(waiter) -> {
      timers.clear_timeout(waiter.timer)
      waiter.resolve(None)
    }
    None -> Nil
  }
  case state.escape_timer {
    Some(timer) -> timers.clear_timeout(timer)
    None -> Nil
  }
  case state.session {
    None -> Nil
    Some(session) -> {
      let _ = stream.off_data(session.input, session.changed)
      let _ = stream.pause(session.input)
      case tty.is_tty(session.input) {
        Ok(True) -> {
          let _ = tty.set_stream_raw_mode(session.input, False)
          Nil
        }
        _ -> Nil
      }
      let _ = process.remove_exit_listener(session.host, session.exited)
      Nil
    }
  }
}

fn start(reader: Reader) {
  let Reader(ref) = reader
  case cell.get(ref).session {
    Some(_) -> Nil
    None -> {
      let assert Ok(host) = process.get()
      let input = process.stdin(host)
      let changed = fn(text) { receive(reader, text) }
      let exited = fn(_) { release(reader) }
      let state = cell.get(ref)
      let _ =
        cell.set(
          ref,
          State(..state, session: Some(Session(host, input, changed, exited))),
        )
      let assert Ok(_) = stream.set_encoding(input, "utf8")
      case tty.is_tty(input) {
        Ok(True) -> {
          let assert Ok(_) = tty.set_stream_raw_mode(input, True)
          Nil
        }
        _ -> Nil
      }
      let assert Ok(_) = stream.on_data(input, changed)
      let assert Ok(_) = process.once_exit(host, exited)
      let assert Ok(_) = stream.resume(input)
      Nil
    }
  }
}

pub fn read(reader: Reader, milliseconds: Int) {
  start(reader)
  let Reader(ref) = reader
  let state = cell.get(ref)
  case state.queue {
    [key, ..queue] -> {
      let _ = cell.set(ref, State(..state, queue:))
      promise.resolve(Some(key))
    }
    [] if milliseconds <= 0 -> promise.resolve(None)
    [] -> {
      assert state.waiting == None as "Only one key read may wait on a terminal"
      let #(pending, resolve) = promise.start()
      let id = state.next + 1
      let timer =
        timers.set_timeout(milliseconds, fn() {
          let current = cell.get(ref)
          case current.waiting {
            Some(waiter) if waiter.id == id -> {
              let _ = cell.set(ref, State(..current, waiting: None))
              waiter.resolve(None)
            }
            _ -> Nil
          }
        })
      let _ =
        cell.set(
          ref,
          State(..state, next: id, waiting: Some(Waiter(id, resolve, timer))),
        )
      pending
    }
  }
}

fn receive(reader: Reader, text) {
  let Reader(ref) = reader
  let state = cell.get(ref)
  case state.escape_timer {
    Some(timer) -> timers.clear_timeout(timer)
    None -> Nil
  }
  let #(decoded, events) = decoder.feed(state.decoder, text)
  let _ = cell.set(ref, State(..state, decoder: decoded, escape_timer: None))
  let interrupted = dispatch(reader, events)
  case interrupted || decoded.buffer == "" {
    True -> Nil
    False -> {
      let timer =
        timers.set_timeout(25, fn() {
          let current = cell.get(ref)
          let #(decoded, events) = decoder.flush(current.decoder)
          let _ =
            cell.set(
              ref,
              State(..current, decoder: decoded, escape_timer: None),
            )
          let _ = dispatch(reader, events)
          Nil
        })
      let current = cell.get(ref)
      let _ = cell.set(ref, State(..current, escape_timer: Some(timer)))
      Nil
    }
  }
}

fn dispatch(reader: Reader, events) {
  case events {
    [] -> False
    [decoder.Interrupt, ..] -> {
      let Reader(ref) = reader
      let session = cell.get(ref).session
      release(reader)
      case session {
        Some(session) -> {
          let _ = process.signal_self(session.host, "SIGINT")
          Nil
        }
        None -> Nil
      }
      True
    }
    [decoder.Key(key), ..rest] -> {
      let Reader(ref) = reader
      let current = cell.get(ref)
      case current.waiting {
        Some(waiter) -> {
          timers.clear_timeout(waiter.timer)
          let _ = cell.set(ref, State(..current, waiting: None))
          waiter.resolve(Some(key))
        }
        None -> {
          let _ =
            cell.set(
              ref,
              State(..current, queue: list.append(current.queue, [key])),
            )
          Nil
        }
      }
      dispatch(reader, rest)
    }
  }
}
