//// ViewModel for the core state

import eyg/hub/cache
import eyg/ir/tree as ir
import gleam/dict
import gleam/list
import gleam/string
import overlay/llm/chat
import overlay/web/state.{type State, State}

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
