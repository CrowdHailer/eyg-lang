import gleam/io
import gleam/dynamic
import gleam/int
import gleam/option.{None, Some}
import gleam/list
import lustre/attribute as a
import lustre/element/html as h
import lustre/element.{text}
import lustre/event
import notepad/state
import notepad/view/helpers
import morph/editable as e
import notepad/view/code
import morph/transform

pub fn render(state: state.State) {
  h.div([a.class("vstack bg-orange-3 max-w-2xl")], [
    note(state.content, state.TextInput),
    editor(state.zip),
    book(),
  ])
}

// TODO show that you can print more an more tree, limit on depth or total size

// a separate component is possible if textarea is absolute,
// a sized container is needed to grow into but it get rids of margin at bottom or container
pub fn note(content, on_input) {
  h.div([a.class("bg-white relative w-full border font-mono")], [
    h.div(
      [
        a.class("absolute left-0 right-0 top-0 bottom-0"),
        a.style([#("white-space", "pre-wrap"), #("word-wrap", "break-word")]),
      ],
      [text(content)],
    ),
    h.textarea([
      // position relative needed for stacking on top of absolutly positioned element
      a.class("w-full bg-transparent text-transparent relative outline-none"),
      a.style([#("caret-color", "black")]),
      a.attribute("rows", helpers.line_count(content)),
      a.value(dynamic.from(content)),
      event.on_input(on_input),
    ]),
  ])
}

fn push_render(m, zoom) {
  case zoom {
    [] -> m
    [transform.CallFn(args), ..rest] -> {
      push_render(code.render_call(m, code.render_args(args)), rest)
    }
    [transform.CallArg(f, pre, post), ..rest] -> {
      let pre = list.map(pre, code.expression)
      let post = list.map(post, code.expression)
      let args = list.flatten([pre, [m], post])
      push_render(
        code.render_call(code.expression(f), code.render_args_e(args)),
        rest,
      )
    }

    [transform.ListItem(pre, post), ..rest] -> {
      let pre = list.map(pre, code.expression)
      let post = list.map(post, code.expression)
      push_render(code.render_list(list.flatten([pre, [m], post])), rest)
    }
    [transform.BlockTail(assigns), ..rest] -> {
      let lines =
        list.map(assigns, fn(a: #(String, e.Expression)) {
          code.assign(a.0, a.1)
        })
        |> list.append([m])
      case rest {
        // escape early to not wrap block
        [] -> code.Multi([], code.to_fat_lines(lines), [])
      }
    }
  }
}

fn print(zip) {
  let #(focus, zoom) = zip
  case focus {
    transform.Exp(exp) -> {
      let core = code.expression(exp)
      let highlighted = case core {
        code.Single(spans) ->
          code.Single([h.span([a.class("bg-green-3")], spans)])
        code.Multi(pre, inner, post) -> {
          // TODO better border
          code.Multi(pre, [h.div([a.class("bg-green-3")], inner)], post)
        }
      }
      push_render(highlighted, zoom)
      |> code.to_fat_line
    }
  }
}

pub fn editor(zip) {
  h.div([a.class("bg-white rounded cover font-mono whitespace-pre border-2")], [
    // nested to ignore effect from cover
    h.div([a.attribute("tabindex", "0"), event.on_keydown(state.KeyDown)], [
      print(zip),
    ]),
  ])
}

pub fn book() {
  h.div([a.class("bg-white rounded cover font-mono whitespace-pre")], [
    // nested to ignore effect from cover
    h.div(
      [],
      code.top(e.Block(
        [
          #("my_int", e.Integer(2)),
          #("my_string", e.String("hello")),
          #("simple_func", e.Function([e.Bind("x"), e.Bind("y")], e.Integer(4))),
          // TODO don't have tuple in destruvture
          #(
            "pattern_func",
            e.Function(
              [e.Destructure([#("x", "a")]), e.Destructure([#("y", "b")])],
              e.Integer(4),
            ),
          ),
          #(
            "multiline_func",
            e.Function([], e.Block([#("x", e.Integer(5))], e.Variable("y"))),
          ),
          #("nested_let", e.Block([#("x", e.Integer(5))], e.Variable("y"))),
          #("empty_list", e.List([], None)),
          #("simple_list", e.List([e.Integer(2), e.Variable("x")], None)),
          #(
            "large_list",
            e.List(
              [
                e.Integer(2),
                e.Block([#("x", e.Integer(233))], e.String("Done!")),
              ],
              None,
            ),
          ),
          #(
            "multi_func",
            e.Function(
              [e.Bind("x"), e.Bind("y")],
              e.List([e.Integer(2), e.Integer(3)], None),
            ),
          ),
          #(
            "call simple",
            e.Call(e.Variable("f"), [e.Variable("x"), e.Integer(23)]),
          ),
          #(
            "call_block_tail",
            e.Call(e.Variable("f"), [
              e.Variable("x"),
              e.Function(
                [e.Bind("x")],
                e.Block([#("x", e.Integer(5))], e.Variable("y")),
              ),
            ]),
          ),
          #(
            "fat_call",
            e.Call(e.Variable("f"), [
              e.Function(
                [e.Bind("x")],
                e.Block([#("x", e.Integer(5))], e.Variable("y")),
              ),
              e.Function(
                [e.Bind("x")],
                e.Block([#("x", e.Integer(5))], e.Variable("y")),
              ),
            ]),
          ),
        ],
        // ],
        e.Function([], e.Block([#("x", e.Integer(5))], e.Variable("y"))),
      )),
    ),
  ])
}
