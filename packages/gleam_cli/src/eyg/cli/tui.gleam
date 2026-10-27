import etui/backend
import etui/buffer
import etui/geometry
import etui/input
import eyg/cli/internal/config
import eyg/cli/shell
import eyg/cli/tui/state
import eyg/cli/tui/view
import eyg/hub/cache
import gleam/bool
import gleam/io
import gleam/javascript/promise
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string
import javascript/mutable_reference
import loam/execute
import loam/source
import loam/system
import plinthx/node/process
import plinthx/node/tty

type Timer

@external(javascript, "node:timers", "setTimeout")
fn set_timeout(callback: fn() -> Nil, milliseconds: Int) -> Timer

@external(javascript, "node:timers", "clearTimeout")
fn clear_timeout(timer: Timer) -> Nil

pub fn execute(
  input: Option(source.Input),
  config: config.Config,
) -> promise.Promise(Result(Int, String)) {
  let state = execute.State(config.client.origin, cache.empty())
  use #(scope, state) <- promise.try_await(
    system.run(shell.read_input(input, state)),
  )

  let assert Ok(global_process) = process.get()
  let stdin = tty.stdin(global_process)
  let stdout = tty.stdout(global_process)
  use <- bool.guard(
    !tty.is_read_tty(stdin) || !tty.is_write_tty(stdout),
    promise.resolve(Error("The TUI needs terminal input and output")),
  )
  let raw = tty.is_raw(stdin)

  let state = mutable_reference.new(state.init(scope, state))
  let input = mutable_reference.new("")
  let timeout = mutable_reference.new(None)
  let cancel_timeout = fn() {
    case mutable_reference.set(timeout, None) {
      Some(timer) -> clear_timeout(timer)
      None -> Nil
    }
  }
  let screen = geometry.rect_new(0, 0, tty.columns(stdout), tty.rows(stdout))
  let screen_ref = mutable_reference.new(screen)

  let draw = fn() {
    let current =
      view.render(
        mutable_reference.get(state),
        mutable_reference.get(screen_ref),
      )

    backend.ops_to_ansi([
      backend.BeginSynchronizedOutput,
      backend.ClearScreen,
      backend.Write(buffer.to_ansi(current)),
      backend.EndSynchronizedOutput,
    ])
    |> io.print
  }

  let finished = mutable_reference.new(False)
  let listeners = mutable_reference.new([])
  promise.new(fn(resolve) {
    let finish = fn(result) {
      case mutable_reference.set(finished, True) {
        True -> Nil
        False -> resolve(result)
      }
    }
    // A promise executor catches exceptions even when invoked by a later event.
    let guard = fn(action) {
      let _ =
        promise.new(fn(done) {
          case mutable_reference.get(finished) {
            True -> Nil
            False -> action()
          }
          done(Nil)
        })
        |> promise.rescue(fn(error) { finish(Error(string.inspect(error))) })
      Nil
    }
    let subscribe = fn(remove) {
      let _ = mutable_reference.update(listeners, fn(all) { [remove, ..all] })
      Nil
    }
    let dispatch = fn(events) { dispatch(events, state, draw, finish, guard) }
    let on_text = fn(chunk) {
      use <- guard
      cancel_timeout()
      let input.Parsed(events, remainder) =
        input.parse(mutable_reference.get(input) <> chunk)
      let _ = mutable_reference.set(input, remainder)
      // A paste ends at its closing marker, never at an inactivity timeout.
      case remainder == "" || string.starts_with(remainder, "\u{1b}[200~") {
        True -> Nil
        False -> {
          let timer =
            set_timeout(
              fn() {
                use <- guard
                let _ = mutable_reference.set(timeout, None)
                let pending = mutable_reference.set(input, "")
                dispatch(input.flush(pending) |> list.map(state.Input))
              },
              40,
            )
          let _ = mutable_reference.set(timeout, Some(timer))
          Nil
        }
      }
      dispatch(events |> list.map(state.Input))
    }
    guard(fn() {
      subscribe(tty.on_end(stdin, fn() { finish(Ok(0)) }))
      subscribe(tty.on_read_error(stdin, fn(reason) { finish(Error(reason)) }))
      subscribe(
        tty.on_write_error(stdout, fn(reason) { finish(Error(reason)) }),
      )
      subscribe(
        tty.on_resize(stdout, fn(_) {
          use <- guard
          let screen =
            geometry.rect_new(0, 0, tty.columns(stdout), tty.rows(stdout))
          let _ = mutable_reference.set(screen_ref, screen)
          draw()
        }),
      )
      tty.set_raw_mode(stdin, True)
      backend.op_to_ansi(backend.EnableBracketedPaste) |> io.print
      subscribe(tty.on_text(stdin, on_text))
      draw()
    })
  })
  |> promise.map(fn(result) {
    cancel_timeout()
    list.each(mutable_reference.get(listeners), fn(remove) { remove() })
    tty.pause(stdin)
    tty.set_raw_mode(stdin, raw)
    backend.ops_to_ansi([
      backend.EndSynchronizedOutput,
      backend.DisableBracketedPaste,
    ])
    |> io.print
    result
  })
  |> promise.rescue(fn(error) { Error(string.inspect(error)) })
}

pub type ContinueOrStop(state, return) {
  Continue(state)
  Stop(return)
}

pub fn apply_until(
  over list: List(a),
  from initial: acc,
  with fun: fn(acc, a) -> ContinueOrStop(acc, return),
) -> ContinueOrStop(acc, return) {
  case list {
    [] -> Continue(initial)
    [first, ..rest] ->
      case fun(initial, first) {
        Continue(next_accumulator) -> apply_until(rest, next_accumulator, fun)
        Stop(b) -> Stop(b)
      }
  }
}

fn dispatch(events, state, draw, finish, guard) {
  // No events no redraw needed
  use <- bool.guard(events == [], Nil)
  case
    apply_until(events, #(mutable_reference.get(state), []), fn(acc, event) {
      let #(next, effects) = state.update(event, acc.0)
      case next.quit {
        True -> Stop(0)
        False -> Continue(#(next, list.append(acc.1, effects)))
      }
    })
  {
    Stop(status) -> finish(Ok(status))
    Continue(#(next, effects)) -> {
      let _ = mutable_reference.set(state, next)
      draw()
      list.each(effects, fn(effect) {
        let _ =
          system.run(effect)
          |> promise.map(fn(message) {
            use <- guard
            dispatch([state.Task(message)], state, draw, finish, guard)
          })
          |> promise.rescue(fn(error) { finish(Error(string.inspect(error))) })
        Nil
      })
    }
  }
}
