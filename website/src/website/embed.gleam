import eyg/sync/browser as remote
import eyg/sync/sync
import eygir/decode
import gleam/int
import gleam/io
import gleam/javascript/array
import gleam/javascript/promise
import gleam/javascript/promisex
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import harness/impl/browser as harness
import lustre
import lustre/attribute as a
import lustre/effect
import lustre/element as lelement
import lustre/element/html as h
import lustre/event
import midas/browser
import morph/editable as e
import plinth/browser/document
import plinth/browser/element
import plinth/javascript/console
import website/components/snippet
import website/routes/editor

pub fn run() {
  let scripts = document.query_selector_all("[type='application/json+eyg']")
  let cache = sync.init(sync.test_origin)
  use result <- promise.map(browser.run(remote.load_task()))
  let assert Ok(dump) = result
  let cache = sync.load(cache, dump)

  list.index_map(array.to_list(scripts), fn(script, i) {
    console.log(script)
    let id = "eyg" <> int.to_string(i)
    let json = element.inner_text(script)

    element.insert_adjacent_html(
      script,
      element.AfterEnd,
      "<div id=\"" <> id <> "\"></div>",
    )
    let json = string.replace(json, "&quot;", "\"")
    let assert Ok(source) = decode.from_json(json)
    // ORIGIN is not used when pulling from supabase
    let app = lustre.application(init, update, render)
    let assert Ok(_) = lustre.start(app, "#" <> id, #(source, cache))
  })
}

pub type State {
  State(menu: editor.Submenu, code: snippet.Snippet)
}

fn init(config) {
  let #(source, cache) = config
  let source =
    e.from_expression(source)
    |> e.open_all
  let snippet = snippet.init(source, [], effects(), cache)
  let state = State(editor.Closed, snippet)
  #(state, effect.none())
}

fn dispatch_to_snippet(promise) {
  effect.from(fn(d) {
    promisex.aside(promise, fn(message) { d(SnippetMessage(message)) })
  })
}

fn dispatch_nothing(_promise) {
  effect.none()
}

pub type Message {
  MenuMessage(editor.MenuMessage)
  SnippetMessage(snippet.Message)
}

fn update(state, message) {
  let State(menu, snippet) = state
  case message {
    MenuMessage(editor.ActionClicked(k)) ->
      update(state, SnippetMessage(snippet.UserPressedCommandKey(k)))

    MenuMessage(editor.ChangeSubmenu(new)) -> {
      let submenu = case new == menu {
        False -> new
        True -> editor.Closed
      }
      #(State(..state, menu: submenu), effect.none())
    }
    SnippetMessage(message) -> {
      let #(snippet, eff) = snippet.update(snippet, message)
      let #(failure, snippet_effect) = case eff {
        snippet.Nothing -> #(None, effect.none())
        snippet.Failed(failure) -> #(Some(failure), effect.none())
        snippet.AwaitRunningEffect(p) -> #(
          None,
          dispatch_to_snippet(snippet.await_running_effect(p)),
        )
        snippet.FocusOnCode -> #(
          None,
          dispatch_nothing(snippet.focus_on_buffer()),
        )
        snippet.FocusOnInput -> #(
          None,
          dispatch_nothing(snippet.focus_on_input()),
        )
        snippet.ToggleHelp -> #(None, effect.none())
        snippet.MoveAbove -> #(None, effect.none())
        snippet.MoveBelow -> #(None, effect.none())
        snippet.ReadFromClipboard -> #(
          None,
          dispatch_to_snippet(snippet.read_from_clipboard()),
        )
        snippet.WriteToClipboard(text) -> #(
          None,
          dispatch_to_snippet(snippet.write_to_clipboard(text)),
        )
        snippet.Conclude(_, _, _) -> #(None, effect.none())
      }
      io.debug(failure)
      #(State(editor.Closed, snippet), snippet_effect)
    }
  }
}

fn render(state) {
  let State(menu, snippet) = state

  h.div([a.class("eyg-embed"), a.style([#("position", "relative")])], [
    // TODO show error
    // TODO fix rendering of input and picker to not use tailwind
    render_menu(snippet, menu, True) |> lelement.map(MenuMessage),
    ..snippet.bare_render(snippet, None)
    |> list.map(fn(e) { lelement.map(e, SnippetMessage) })
  ])
}

fn effects() {
  // TODO make website effects but login will require crowdhailer.me to work for tweet effect
  harness.effects()
}

fn render_menu(snippet, submenu, display_help) {
  let snippet.Snippet(status: status, source: source, ..) = snippet
  let #(top, subcontent) = editor.menu_content(status, source.0, submenu)
  h.div(
    [
      a.class("eyg-menu-container"),
      a.style([
        #("position", "absolute"),
        #("left", "0"),
        #("top", "50%"),
        #("transform", "translate(calc(-100% - 10px), -50%)"),
        #("grid-template-columns", "max-content max-content"),
        #("overflow-x", "hidden"),
        #("overflow-y", "auto"),
        #("display", "grid"),
      ]),
    ],
    [
      h.div(
        [
          a.style([
            #("padding-top", ".5rem"),
            #("padding-bottom", ".5rem"),
            #("justify-content", "flex-end"),
            #("flex-direction", "column"),
            #("display", "flex"),
          ]),
        ],
        list.map(top, fn(entry) {
          let #(i, text, k) = entry
          h.button([a.class("hover:bg-gray-800 px-2 py-1"), event.on_click(k)], [
            editor.icon(i, text, display_help),
          ])
        }),
      ),
      case subcontent {
        None -> lelement.none()
        // TODO reuse column rendering fn
        Some(#(key, subitems)) ->
          h.div(
            [
              a.style([
                #("padding-top", ".5rem"),
                #("padding-bottom", ".5rem"),
                #("justify-content", "flex-end"),
                #("flex-direction", "column"),
                #("display", "flex"),
              ]),
            ],
            list.map(subitems, fn(entry) {
              let #(i, text, k) = entry
              h.button(
                [a.class("hover:bg-gray-800 px-2 py-1"), event.on_click(k)],
                [editor.icon(i, text, display_help)],
              )
            }),
          )
      },
    ],
  )
}