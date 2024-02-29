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

pub fn render(state: state.State) {
  h.div([a.class("vstack bg-orange-3 max-w-2xl")], [
    note(state.content, state.TextInput),
    book(),
  ])
}

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

pub fn book() {
  h.div([a.class("bg-white rounded cover font-mono whitespace-pre")], [
    // nested to ignore effect from cover
    h.div(
      [],
      top(e.Block(
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

fn assign(label, value) {
  case expression(value) {
    Single(spans) ->
      Single([
        h.span([], [text("let ")]),
        h.span([a.class("text-blue-4")], [text(label)]),
        h.span([], [text(" = ")]),
        ..spans
      ])
    Multi(pre, inner, post) -> {
      let pre = [
        h.span([], [text("let ")]),
        h.span([a.class("text-blue-4")], [text(label)]),
        h.span([], [text(" = ")]),
        ..pre
      ]
      Multi(pre, inner, post)
    }
  }
}

pub type Multiline(a) {
  Multi(
    List(element.Element(a)),
    List(element.Element(a)),
    List(element.Element(a)),
  )
  Single(List(element.Element(a)))
}

fn indent(inner) {
  h.div([a.style([#("padding-left", "2ch")])], inner)
}

// wrap each line thing in it's own div
fn to_fat_line(exp) {
  case exp {
    Single(spans) -> h.div([], spans)
    Multi(pre, inner, post) ->
      h.div([], [h.div([], pre), indent(inner), h.div([], post)])
  }
}

fn to_fat_lines(lines) {
  list.map(lines, to_fat_line)
}

fn top(code) {
  case code {
    e.Block(assigns, tail) -> block_content(assigns, tail)
    exp -> [expression(exp)]
  }
  |> to_fat_lines()
}

fn block_content(assigns, tail) {
  list.map(assigns, fn(a: #(String, e.Expression)) { assign(a.0, a.1) })
  |> list.append([expression(tail)])
}

fn pattern(p) {
  case p {
    e.Bind(x) -> [h.span([], [text(x)])]
    e.Destructure(fields) -> {
      list.map(fields, fn(f) {
        let #(field, var) = f
        [
          h.span([], [text(field)]),
          h.span([], [text(": ")]),
          h.span([], [text(var)]),
        ]
      })
      |> list.intersperse([h.span([], [text(", ")])])
      |> list.flatten
      |> list.append([text("}")])
      |> list.append([text("{")], _)
    }
  }
}

fn patterns(ps) {
  list.map(ps, pattern)
  |> list.intersperse([text(", ")])
  |> list.flatten
  |> list.append([text(")")])
  |> list.append([text("(")], _)
}

// join function
fn assume_single(m) {
  case m {
    Single(spans) -> Ok(spans)
    _ -> Error(Nil)
  }
}

fn postpend_span(m, span) {
  case m {
    Single(spans) -> Single(list.append(spans, [span]))
    Multi(pre, inner, post) -> Multi(pre, inner, list.append(post, [span]))
  }
}

fn expression(exp) {
  case exp {
    e.Block(assigns, tail) ->
      Multi(
        [h.span([], [text("{")])],
        to_fat_lines(block_content(assigns, tail)),
        [h.span([], [text("}")])],
      )
    e.Call(f, args) -> {
      let assert [last, ..rest] = list.reverse(args)
      let last = expression(last)
      let rest = list.map(rest, expression)
      let m = case list.try_map(rest, assume_single) {
        Ok(spanss) ->
          list.fold(spanss, last, fn(tail, spans) {
            case tail {
              Single(old) -> Single(list.flatten([spans, [text(", ")], old]))
              Multi(pre, inner, post) ->
                Multi(list.flatten([spans, [text(", ")], pre]), inner, post)
            }
          })

        Error(Nil) -> {
          let args =
            list.reverse([last, ..rest])
            |> list.map(postpend_span(_, text(",")))
            |> to_fat_lines
            |> Multi([], _, [])
        }
      }
      let assert Single(fspans) = expression(f)
      case m {
        Single(spans) ->
          Single(list.flatten([fspans, [text("(")], spans, [text(")")]]))
        Multi(pre, inner, post) ->
          Multi(
            list.flatten([fspans, [text("(")], pre]),
            inner,
            list.append(post, [text(")")]),
          )
      }
    }
    // defninetly multiline don't wrap in double curlies
    e.Function(args, e.Block(assigns, tail)) ->
      Multi(
        [h.span([], [text("("), text("arg"), text(") -> {")])],
        to_fat_lines(block_content(assigns, tail)),
        [h.span([], [text("}")])],
      )
    e.Function(args, body) -> {
      let args = patterns(args)
      case expression(body) {
        Single(spans) ->
          Single(list.flatten([args, [text(" -> { ")], spans, [text(" }")]]))
        Multi(pre, inner, post) ->
          Multi(
            list.flatten([args, [text(" -> {")], pre]),
            inner,
            list.append(post, [text("}")]),
          )
      }
    }
    e.Variable(x) -> Single([h.span([a.class("text-gray-700")], [text(x)])])
    e.List([], tail) -> Single([text("[]")])
    e.List(items, tail) -> {
      list.map(items, expression)
      |> list.map(to_list_item)
      |> Multi([text("[")], _, [text("]")])
    }
    e.Integer(v) ->
      Single([h.span([a.class("text-purple-2")], [text(int.to_string(v))])])
    e.String(v) ->
      Single([
        h.span([a.class("text-green-4")], [text("\""), text(v), text("\"")]),
      ])

    _ -> {
      io.debug(exp)
      panic as "exp"
    }
  }
}

fn to_list_item(m) {
  case m {
    Single(spans) -> Single(list.append(spans, [text(",")]))
    Multi(pre, inner, post) -> {
      let post = list.append(post, [text(",")])
      Multi(pre, inner, post)
    }
  }
  |> to_fat_line
}
