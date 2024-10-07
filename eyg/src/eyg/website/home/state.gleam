import eyg/shell/examples
import eyg/website/components/snippet
import gleam/dict.{type Dict}
import gleam/io
import gleam/option.{None, Some}
import harness/impl/browser/alert
import harness/impl/browser/copy
import harness/impl/browser/download
import harness/impl/browser/paste
import harness/impl/browser/prompt
import lustre/effect
import morph/editable as e
import morph/projection

pub type State {
  State(active: Active, snippets: Dict(Int, snippet.Snippet))
}

pub type Active {
  Editing(Int)
  Running(Int)
  Nothing
}

fn effects() {
  [
    #(alert.l, #(alert.lift, alert.reply, alert.blocking)),
    #(copy.l, #(copy.lift, copy.reply(), copy.blocking)),
    #(download.l, #(download.lift, download.reply(), download.blocking)),
    #(paste.l, #(paste.lift, paste.reply(), paste.blocking)),
    #(prompt.l, #(prompt.lift, prompt.reply(), prompt.blocking)),
  ]
}

const closure_serialization = e.Block(
  [
    #(
      e.Bind("script"),
      e.Function(
        [e.Bind("closure")],
        e.Block(
          [
            #(
              e.Bind("js"),
              e.Call(e.Builtin("to_javascript"), [e.Variable("closure")]),
            ),
          ],
          e.Call(
            e.Builtin("string_append"),
            [
              e.String("<script>"),
              e.Call(
                e.Builtin("string_append"),
                [e.Variable("js"), e.String("</script>")],
              ),
            ],
          ),
          True,
        ),
      ),
    ),
    #(
      e.Bind("name"),
      e.Case(
        e.Call(e.Perform("Prompt"), [e.String("What is your name?")]),
        [
          #("Ok", e.Function([e.Bind("value")], e.Variable("value"))),
          #("Error", e.Function([e.Bind("_")], e.String("Alice"))),
        ],
        None,
      ),
    ),
    #(
      e.Bind("client"),
      e.Function(
        [e.Bind("_")],
        e.Block(
          [
            #(
              e.Bind("message"),
              e.Call(
                e.Builtin("string_append"),
                [e.String("Hello, "), e.Variable("name")],
              ),
            ),
            // perform can't be last effect
            #(e.Bind("_"), e.Call(e.Perform("Alert"), [e.Variable("message")])),
          ],
          e.Record([], None),
          True,
        ),
      ),
    ), #(e.Bind("page"), e.Call(e.Variable("script"), [e.Variable("client")])),
    #(
      e.Bind("page"),
      e.Call(e.Builtin("string_to_binary"), [e.Variable("page")]),
    ),
  ],
  e.Call(
    e.Perform("Download"),
    [
      e.Record(
        [#("name", e.String("index.html")), #("content", e.Variable("page"))],
        None,
      ),
    ],
  ),
  True,
)

pub fn init(_) {
  #(
    State(
      Nothing,
      dict.from_list([
        #(0, snippet.init(closure_serialization, effects())),
        #(
          1,
          snippet.init(
            projection.rebuild(examples.catfact_fetch().0),
            effects(),
          ),
        ),
      ]),
    ),
    effect.none(),
  )
}

pub fn get_snippet(state: State, id: Int) {
  let assert Ok(snippet) = dict.get(state.snippets, id)
  snippet
}

pub fn set_snippet(state: State, id, snippet) {
  State(..state, snippets: dict.insert(state.snippets, id, snippet))
}

pub type Message {
  SnippetMessage(Int, snippet.Message)
}

pub fn update(state: State, message) {
  case message {
    SnippetMessage(id, message) -> {
      let state = case state.active {
        Editing(current) if current != id -> {
          let snippet = get_snippet(state, current)
          let snippet = snippet.finish_editing(snippet)
          set_snippet(state, current, snippet)
        }
        Running(_current) -> panic as "should not click around when running"
        _ -> state
      }
      let snippet = get_snippet(state, id)
      let #(snippet, eff) = snippet.update(snippet, message)
      let state = set_snippet(state, id, snippet)
      let state = State(..state, active: Editing(id))
      #(state, case eff {
        None -> effect.none()
        Some(f) ->
          effect.from(fn(d) {
            let d = fn(m) { d(SnippetMessage(id, m)) }
            f(d)
          })
      })
    }
  }
}
