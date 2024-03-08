import gleam/io
import gleam/dynamic
import gleam/int
import gleam/option.{None, Some}
import gleam/list
import gleam/listx
import lustre/attribute as a
import lustre/element/html as h
import lustre/element.{text}
import lustre/event
import notepad/state
import notepad/view/helpers
import morph/editable as e
import morph/lustre/render
import morph/projection as t
import morph/lustre/frame

pub fn render(state: state.State) {
  h.div([a.class("vstack bg-orange-3 max-w-2xl")], [
    note(state.content, state.TextInput),
    editor(state.zip, state.mode),
    book(),
  ])
}

// TODO select from record
// TODO remove t.Match for Label and call render_case
// TODO join_field needs to take span if used by expression and pattern
// TODO show that you can print more an more tree, limit on depth or total size
// TODO click on page
// Need Ok/Error in actions for filtering if it's possible

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
      let frame = render.render_break(break, frame)
      push_render(frame, rest)
    }
  }
}

pub fn print(zip) -> element.Element(a) {
  let #(focus, zoom) = zip
  let frame = case focus {
    t.Exp(exp) -> highlight(render.expression(exp))
    t.Assign(detail, value, pre, post, then) -> {
      let pre = list.map(pre, do_assign)
      let post = list.map(post, do_assign)

      let assign = case detail {
        // get rid of assign statement then do_let goes on the outside
        t.AssignStatement(pattern) -> highlight(render.assign(pattern, value))
        t.AssignPattern(pattern) -> {
          let pattern = [highlight_spans(render.pattern(pattern))]
          render.do_let(pattern, render.expression(value))
        }
        t.AssignField(label, var, pre, post) -> {
          let spans = [
            highlight_spans([text(label)]),
            h.span([], [text(": ")]),
            h.span([], [text(var)]),
          ]
          let pre = list.map(pre, render.do_field)
          let post = list.map(post, render.do_field)
          let pattern =
            render.do_destructured(listx.gather_around(pre, spans, post))
          render.do_let(pattern, render.expression(value))
        }
        t.AssignBind(label, var, pre, post) -> {
          let spans = [
            h.span([], [text(label)]),
            h.span([], [text(": ")]),
            highlight_spans([text(var)]),
          ]
          let pre = list.map(pre, render.do_field)
          let post = list.map(post, render.do_field)
          let pattern =
            render.do_destructured(listx.gather_around(pre, spans, post))
          render.do_let(pattern, render.expression(value))
        }
      }

      listx.gather_around(pre, assign, post)
      |> list.append([render.expression(then)])
      |> frame.to_fat_lines
      |> frame.Multiline([text("{")], _, [text("}")])
    }
    t.FnParam(detail, pre, post, body) -> {
      let pre = list.map(pre, render.pattern)
      let post = list.map(post, render.pattern)
      let pattern = case detail {
        t.AssignStatement(pattern) -> [highlight_spans(render.pattern(pattern))]
        t.AssignPattern(pattern) -> {
          [highlight_spans(render.pattern(pattern))]
        }
        t.AssignField(label, var, pre, post) -> {
          let spans = [
            highlight_spans([text(label)]),
            h.span([], [text(": ")]),
            h.span([], [text(var)]),
          ]
          let pre = list.map(pre, render.do_field)
          let post = list.map(post, render.do_field)
          render.do_destructured(listx.gather_around(pre, spans, post))
        }
        t.AssignBind(label, var, pre, post) -> {
          let spans = [
            h.span([], [text(label)]),
            h.span([], [text(": ")]),
            highlight_spans([text(var)]),
          ]
          let pre = list.map(pre, render.do_field)
          let post = list.map(post, render.do_field)
          render.do_destructured(listx.gather_around(pre, spans, post))
        }
      }
      let patterns = listx.gather_around(pre, pattern, post)
      let patterns = render.join_patterns(patterns)
      render.render_function(patterns, render.expression(body))
    }
    t.Labeled(label, value, pre, post, for) -> {
      let field = render.render_field(#(label, value))
      let pre = list.map(pre, render.render_field)
      let post = list.map(post, render.render_field)
      let original = case for {
        t.Record -> None
        t.Overwrite(original) -> Some(render.expression(original))
      }
      render.render_record(
        listx.gather_around(pre, highlight(field), post),
        original,
      )
    }
    t.Label(label, value, pre, post, for) -> {
      let value = render.expression(value)
      let label = highlight_spans([text(label)])
      let field = frame.prepend_spans([label, text(": ")], value)

      let pre = list.map(pre, render.render_field)
      let post = list.map(post, render.render_field)
      let original = case for {
        t.Record -> None
        t.Overwrite(original) -> Some(render.expression(original))
      }

      render.render_record(listx.gather_around(pre, field, post), original)
    }
    t.Match(top, label, value, pre, post, otherwise) -> {
      let value = render.expression(value)
      let branch =
        frame.prepend_spans([highlight_spans([text(label)]), text(" ")], value)
      let pre = list.map(pre, render.render_branch)
      let post = list.map(post, render.render_branch)
      render.render_case(
        render.expression(top),
        listx.gather_around(pre, branch, post),
        option.map(otherwise, render.expression),
      )
    }
    _ -> {
      io.debug(zip)
      panic as "bad print"
    }
  }
  push_render(frame, zoom)
  |> frame.to_fat_line
  // TO fat line is very similar to top function
}

// TODO move to a standard highlight function
fn highlight(m) {
  case m {
    frame.Inline(spans) -> frame.Inline([highlight_spans(spans)])
    frame.Multiline(pre, inner, post) -> {
      frame.Multiline(
        [h.span([a.class("border-green-600 border-2")], pre)],
        [
          h.div(
            [a.class("border-green-600 border-2"), a.id("highlighted")],
            inner,
          ),
        ],
        [h.span([a.class("border-green-600 border-2")], post)],
      )
    }
  }
}

fn highlight_spans(spans) {
  h.span([a.class("border-green-600 border-2"), a.id("highlighted")], spans)
}

fn do_assign(kv) {
  let #(label, value) = kv
  render.assign(label, value)
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
      // h.div([a.classes([#("hidden", hide)])], [
      case hide {
        False ->
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
                  // a.autofocus(True),
                  a.attribute("autofocus", "true"),
                  event.on_input(state.TextChange),
                ]),
                h.button([a.type_("submit")], [text("apply")]),
              ]),
            ],
          )
        True -> h.div([], [])
      },
      // ]),
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
      render.top(e.Block(
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
