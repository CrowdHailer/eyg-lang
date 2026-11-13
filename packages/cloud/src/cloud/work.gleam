//// Work returned by a channel's checked, pure `handle` function.
//// The input to that function belongs to the plugin; only work is shared.

import eyg/analysis/type_/isomorphic as t
import eyg/interpreter/break
import eyg/interpreter/cast
import eyg/interpreter/simple_debug
import gleam/option.{type Option}
import gleam/result

pub type Work {
  Input(session: Option(String), text: String)
  Observe(session: Option(String), text: String)
  /// Apply /new, an explicit EYG block, or agent input to a session.
  Submit(
    session: Option(String),
    reply: Option(String),
    text: String,
    description: String,
  )
  Run(
    session: Option(String),
    reply: Option(String),
    code: String,
    description: String,
  )
  Reset(session: Option(String))
  Post(thread: Option(String), text: String)
}

pub fn type_() {
  let session = t.option(t.String)
  let input = t.record([#("session", session), #("text", t.String)])
  t.union([
    #("Input", input),
    #("Observe", input),
    #(
      "Submit",
      t.record([
        #("session", session),
        #("reply", session),
        #("text", t.String),
        #("description", t.String),
      ]),
    ),
    #("Reset", session),
    #("Post", t.record([#("thread", session), #("text", t.String)])),
    #(
      "Run",
      t.record([
        #("session", session),
        #("reply", session),
        #("code", t.String),
        #("description", t.String),
      ]),
    ),
  ])
}

pub fn decode(value) -> Result(List(Work), String) {
  cast.as_list_of(value, fn(value) {
    use #(tag, value) <- result.try(cast.as_tagged(value))
    case tag {
      "Input" | "Observe" -> {
        use session <- result.try(cast.field("session", thread, value))
        use text <- result.map(cast.field("text", cast.as_string, value))
        case tag {
          "Input" -> Input(session, text)
          _ -> Observe(session, text)
        }
      }
      "Reset" -> thread(value) |> result.map(Reset)
      "Post" -> {
        use thread <- result.try(cast.field("thread", thread, value))
        use text <- result.map(cast.field("text", cast.as_string, value))
        Post(thread, text)
      }
      "Run" | "Submit" -> {
        use session <- result.try(cast.field("session", thread, value))
        use reply <- result.try(cast.field("reply", thread, value))
        let field = case tag {
          "Run" -> "code"
          _ -> "text"
        }
        use code <- result.try(cast.field(field, cast.as_string, value))
        use description <- result.map(cast.field(
          "description",
          cast.as_string,
          value,
        ))
        case tag {
          "Run" -> Run(session, reply, code, description)
          _ -> Submit(session, reply, code, description)
        }
      }
      _ -> Error(break.IncorrectTerm("channel work", value))
    }
  })
  |> result.map_error(simple_debug.describe)
}

fn thread(value) {
  cast.as_option(value, cast.as_string)
}
