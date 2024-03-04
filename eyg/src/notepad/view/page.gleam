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
import morph/transform as t
import notepad/view/frame

pub fn render(state: state.State) {
  h.div([a.class("vstack bg-orange-3 max-w-2xl")], [
    note(state.content, state.TextInput),
    editor(state.zip, state.mode),
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

fn push_render(frame, zoom) {
  case zoom {
    [] -> frame
    [break, ..rest] -> {
      let frame = code.render_break(break, frame)
      push_render(frame, rest)
    }
  }
}

fn print(zip) {
  let #(focus, zoom) = zip
  case focus {
    t.Exp(exp) -> {
      let core = code.expression(exp)
      // TODO move highlight
      let highlighted = case core {
        frame.Inline(spans) ->
          frame.Inline([h.span([a.class("bg-green-3")], spans)])
        frame.Multiline(pre, inner, post) -> {
          // TODO better border
          frame.Multiline(pre, [h.div([a.class("bg-green-3")], inner)], post)
        }
      }
      push_render(highlighted, zoom)
      |> frame.to_fat_line
    }
    t.Assign(detail, value, pre, post, then) -> {
      let pre = list.map(pre, do_assign)
      let post = list.map(post, do_assign)

      let assign = case detail {
        t.AssignStatement(pattern) -> highlight(code.assign(pattern, value))
        t.AssignPattern(pattern) -> {
          let pattern = [h.span([a.class("bg-green-3")], code.pattern(pattern))]
          code.do_let(pattern, code.expression(value))
        }
        t.AssignField(label, var, pre, post) -> {
          let spans = [
            h.span([a.class("bg-blue-2")], [text(label)]),
            h.span([], [text(": ")]),
            h.span([], [text(var)]),
          ]
          let pre = list.map(pre, code.do_field)
          let post = list.map(post, code.do_field)
          let pattern = code.do_destructured(t.gather_around(pre, spans, post))
          code.do_let(pattern, code.expression(value))
        }
        t.AssignBind(label, var, pre, post) -> {
          let spans = [
            h.span([], [text(label)]),
            h.span([], [text(": ")]),
            h.span([a.class("bg-blue-2")], [text(var)]),
          ]
          let pre = list.map(pre, code.do_field)
          let post = list.map(post, code.do_field)
          let pattern = code.do_destructured(t.gather_around(pre, spans, post))
          code.do_let(pattern, code.expression(value))
        }
      }

      let block =
        t.gather_around(pre, assign, post)
        |> list.append([code.expression(then)])
        |> frame.to_fat_lines
        |> frame.Multiline([], _, [])
      push_render(block, zoom)
      |> frame.to_fat_line
    }
    t.FnParam(p, pre, post, body) -> {
      let pre = list.map(pre, code.pattern)
      let post = list.map(post, code.pattern)
      let spans = code.pattern(p)
      let p = [h.span([a.class("bg-purple-2")], spans)]
      let patterns = t.gather_around(pre, p, post)
      let patterns = code.join_patterns(patterns)
      let f = code.render_function(patterns, code.expression(body))
      push_render(f, zoom)
      |> frame.to_fat_line
    }
    t.Labeled(label, value, pre, post) -> {
      let field = code.render_field(#(label, value))
      let pre = list.map(pre, code.render_field)
      let post = list.map(post, code.render_field)
      code.render_record(t.gather_around(pre, highlight(field), post))
      |> push_render(zoom)
      |> frame.to_fat_line
    }
    t.Label(label, value, pre, post, _) -> {
      let value = code.expression(value)
      let field =
        frame.prepend_spans(
          [h.span([a.class("bg-green-3")], [text(label), text(": ")])],
          value,
        )

      let pre = list.map(pre, code.render_field)
      let post = list.map(post, code.render_field)
      code.render_record(t.gather_around(pre, field, post))
      |> push_render(zoom)
      |> frame.to_fat_line
    }
    t.Match(top, label, value, pre, post, otherwise) -> {
      let value = code.expression(value)
      let branch =
        frame.prepend_spans(
          [h.span([a.class("bg-green-3")], [text(label)])],
          value,
        )
      let pre = list.map(pre, code.render_branch)
      let post = list.map(post, code.render_branch)
      code.render_case(
        code.expression(top),
        t.gather_around(pre, branch, post),
        option.map(otherwise, code.expression),
      )
      |> push_render(zoom)
      |> frame.to_fat_line
    }
    _ -> {
      io.debug(zip)
      panic as "bad print"
    }
  }
}

// TODO move to a standard highlight function
fn highlight(m) {
  case m {
    frame.Inline(spans) ->
      frame.Inline([h.span([a.class("bg-green-3")], spans)])
    frame.Multiline(pre, inner, post) -> {
      // TODO better border
      frame.Multiline(pre, [h.div([a.class("bg-green-3")], inner)], post)
    }
  }
}

fn do_assign(kv) {
  let #(label, value) = kv
  code.assign(label, value)
}

pub fn editor(zip, mode) {
  let #(hide, value) = case mode {
    state.Command -> #(True, "")
    state.Insert(value, _) -> #(False, value)
  }

  h.div(
    [
      a.class(
        "relative bg-white rounded cover font-mono whitespace-pre border-2",
      ),
    ],
    [
      // Hidden is nested because vstack display overrides the hidden attribute
      // And being a child of cover the margins are messed up
      h.div([a.classes([#("hidden", hide)])], [
        h.div(
          [
            a.class(
              "absolute top-0 bottom-0 right-0 left-0 vstack wrap bg-white",
            ),
            // needed because I need no wrap sizing in layout.css
            a.style([#("margin", "0")]),
          ],
          [
            h.form([event.on_submit(state.ApplyChange)], [
              h.input([
                a.class("border"),
                a.value(dynamic.from(value)),
                a.autofocus(True),
                event.on_input(state.TextChange),
              ]),
              h.button([a.type_("submit")], [text("apply")]),
            ]),
          ],
        ),
      ]),
      // nested to ignore effect from cover
      h.div([a.attribute("tabindex", "0"), event.on_keydown(state.KeyDown)], [
        print(zip),
      ]),
    ],
  )
}

pub fn book() {
  h.div([a.class("bg-white rounded cover font-mono whitespace-pre")], [
    // nested to ignore effect from cover
    h.div(
      [],
      code.top(e.Block(
        [
          #(e.Bind("my_int"), e.Integer(2)),
          #(e.Bind("my_string"), e.String("hello")),
          #(
            e.Bind("simple_func"),
            e.Function([e.Bind("x"), e.Bind("y")], e.Integer(4)),
          ),
          // TODO don't have tuple in destruvture
          #(
            e.Bind("pattern_func"),
            e.Function(
              [e.Destructure([#("x", "a")]), e.Destructure([#("y", "b")])],
              e.Integer(4),
            ),
          ),
          #(
            e.Bind("multiline_func"),
            e.Function(
              [],
              e.Block([#(e.Bind("x"), e.Integer(5))], e.Variable("y")),
            ),
          ),
          #(
            e.Bind("nested_let"),
            e.Block([#(e.Bind("x"), e.Integer(5))], e.Variable("y")),
          ),
          #(e.Bind("empty_list"), e.List([], None)),
          #(
            e.Bind("simple_list"),
            e.List([e.Integer(2), e.Variable("x")], None),
          ),
          #(
            e.Bind("large_list"),
            e.List(
              [
                e.Integer(2),
                e.Block([#(e.Bind("x"), e.Integer(233))], e.String("Done!")),
              ],
              None,
            ),
          ),
          #(
            e.Bind("multi_func"),
            e.Function(
              [e.Bind("x"), e.Bind("y")],
              e.List([e.Integer(2), e.Integer(3)], None),
            ),
          ),
          #(
            e.Bind("call simple"),
            e.Call(e.Variable("f"), [e.Variable("x"), e.Integer(23)]),
          ),
          #(
            e.Bind("call_block_tail"),
            e.Call(e.Variable("f"), [
              e.Variable("x"),
              e.Function(
                [e.Bind("x")],
                e.Block([#(e.Bind("x"), e.Integer(5))], e.Variable("y")),
              ),
            ]),
          ),
          #(
            e.Bind("fat_call"),
            e.Call(e.Variable("f"), [
              e.Function(
                [e.Bind("x")],
                e.Block([#(e.Bind("x"), e.Integer(5))], e.Variable("y")),
              ),
              e.Function(
                [e.Bind("x")],
                e.Block([#(e.Bind("x"), e.Integer(5))], e.Variable("y")),
              ),
            ]),
          ),
        ],
        // ],
        e.Function([], e.Block([#(e.Bind("x"), e.Integer(5))], e.Variable("y"))),
      )),
    ),
  ])
}
