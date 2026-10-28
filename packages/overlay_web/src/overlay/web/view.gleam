//// ViewModel for the core state

import eyg/hub/cache
import eyg/ir/tree as ir
import glasshouse/recorder
import glasshouse/run
import glasshouse/session
import glasshouse/value
import gleam/dict
import gleam/list
import gleam/option
import gleam/result
import gleam/string
import overlay/llm/chat
import overlay/web/context
import overlay/web/state.{type State, State}

pub type Context {
  Default
  Loading(name: String)
  Loaded(name: String, has_readme: Bool)
  Failed(name: String, reason: String)
}

pub fn context(state: State) -> Context {
  let State(context_source:, context:, ..) = state
  let name = context.describe(context_source)
  case context_source, context {
    context.Default, _ -> Default
    _, context.Pulling(..) | _, context.Fetching(..) -> Loading(name)
    _, context.Loaded(..) ->
      Loaded(name, option.is_some(context.provided_readme(context)))
    _, context.Errored(reason:) -> Failed(name, reason)
  }
}

pub fn messages(state: State) {
  let State(status:, history:, ..) = state
  let messages = case status {
    state.Waiting -> history
    state.Asking(messages:) -> list.append(messages, state.history)
    state.Streaming(reader: _, completion:, remaining: _) -> {
      let chat.Completion(thinking:, content:, tool_calls:) = completion
      let message = chat.AssistantMessage(thinking:, text: content, tool_calls:)
      [message, ..history]
    }
    state.Executing(_calls) -> history
  }
  let length = list.length(messages)
  list.index_map(messages, fn(message, i) { #(length - i, message) })
}

pub type Waiting {
  PullingReleases
  Fetching(reference: String)
  Blocked(reference: String, on: String)
}

pub fn waiting_on(state: State) -> List(Waiting) {
  let State(cache:, ..) = state
  let cache.Cache(fetching_modules:, cursor_status:, ..) = cache

  let pulling = case cursor_status {
    cache.ReadyToPull | cache.Pulling -> [PullingReleases]
    cache.Pulled | cache.PullFailed(_) -> []
  }

  let #(fetching, blocked) =
    dict.fold(fetching_modules, #([], []), fn(acc, cid, status) {
      let #(fetching, blocked) = acc
      let reference = ir.reference_to_string(ir.Content(cid:))
      case status {
        cache.NotRequested | cache.Requested -> #(
          [Fetching(reference:), ..fetching],
          blocked,
        )
        cache.DependsOn(dep:, ..) -> #(fetching, [
          Blocked(
            reference:,
            on: ir.reference_to_string(cache.dep_to_reference(dep)),
          ),
          ..blocked
        ])
        // Neither is outstanding. A module the hub could not answer for, or
        // answered badly, is given to the agent as a missing reference.
        cache.Failed(_) | cache.Invalid(_) -> acc
      }
    })

  list.flatten([pulling, sorted(fetching), sorted(blocked)])
}

/// The statuses are held in a dict, which has an order of its own that can
/// change as it grows. Sorting keeps the list steady across renders.
fn sorted(waiting: List(Waiting)) -> List(Waiting) {
  use a, b <- list.sort(waiting)
  string.compare(order_string(a), order_string(b))
}

fn order_string(waiting: Waiting) -> String {
  case waiting {
    PullingReleases -> ""
    Fetching(reference:) -> reference
    Blocked(reference:, on: _) -> reference
  }
}

/// One line to show for a collapsed tool result.
/// For a result with printed output this is the final value, not the "Output:" heading.
pub fn summary(text: String) -> String {
  let text = case string.split_once(text, "\nResult:\n") {
    Ok(#(_output, result)) -> "Result: " <> result
    Error(Nil) -> text
  }
  string.split(text, "\n")
  |> list.find(fn(line) { string.trim(line) != "" })
  |> result.unwrap("")
}

/// A tool call as recorded in the session's trace.
pub type Run {
  Run(
    id: String,
    code: String,
    effects: List(#(String, String)),
    result: String,
  )
}

/// The tool calls recorded so far, oldest first, with a summary of each effect's request.
pub fn trace(state: State) -> #(String, List(Run)) {
  let State(trace:, ..) = state
  let store = recorder.store(trace.recorder)
  let events = list.reverse(trace.events)
  let runs =
    list.filter_map(events, fn(event) {
      case event {
        session.Execution(run: run.Run(kind: run.Tool(id), code:, journal:, ..)) -> {
          let result =
            list.find_map(events, fn(event) {
              case event {
                session.ToolResult(call_id:, text:, ..) if call_id == id ->
                  Ok(text)
                _ -> Error(Nil)
              }
            })
            |> result.unwrap("")
          let effects =
            list.map(journal, fn(entry) {
              #(entry.label, value.summary(entry.lift, store, 80))
            })
          Ok(Run(id:, code:, effects:, result:))
        }
        _ -> Error(Nil)
      }
    })
  #(trace.id, runs)
}
