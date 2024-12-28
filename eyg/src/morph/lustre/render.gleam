import gleam/int
import gleam/list
import gleam/listx
import gleam/option.{None, Some}
import gleam/string
import lustre/attribute as a
import lustre/element.{text}
import lustre/element/html as h
import lustre/event
import morph/editable as e
import morph/lustre/frame
import morph/lustre/highlight
import morph/projection as t

pub fn do_let(rev, pattern, value) {
  let assignment =
    list.flatten([
      [h.span([exp_key(rev)], [text("let ")])],
      pattern,
      [h.span([exp_key(rev)], [text(" = ")])],
    ])
  frame.prepend_spans(assignment, value)
}

pub fn assign(p, value, rev) {
  do_let(rev, pattern(p, [0, ..rev]), expression(value, [1, ..rev]))
}

pub fn assigns(a, rev) {
  list.index_map(a, fn(a, i) { assign_pair(a, [i, ..rev]) })
  |> frame.to_fat_lines()
}

// ignore tail vacant will need for spotless history
pub fn statements(code) {
  let rev = []
  case code {
    e.Block(assigns, e.Vacant(_), _) ->
      list.index_map(assigns, fn(a, i) { assign_pair(a, [i, ..rev]) })
    e.Block(assigns, tail, _) -> block_content(assigns, tail, rev)
    exp -> [expression(exp, rev)]
  }
  |> frame.to_fat_lines()
}

// is for unwrapped block
pub fn top(code) {
  let rev = []

  case code {
    e.Block(assigns, tail, _) -> block_content(assigns, tail, rev)
    exp -> [expression(exp, rev)]
  }
  |> frame.to_fat_lines()
}

fn block_content(assigns, tail, rev) {
  list.index_map(assigns, fn(a, i) { assign_pair(a, [i, ..rev]) })
  |> list.append([expression(tail, [list.length(assigns), ..rev])])
}

fn assign_pair(kv, rev) {
  let #(label, value) = kv
  assign(label, value, rev)
}

pub fn pattern(p, rev) {
  case p {
    e.Bind(x) -> [h.span([exp_key(rev)], [text(x)])]
    e.Destructure(fields) -> {
      list.index_map(fields, fn(f, i) { do_field(f, i, rev) })
      |> do_destructured(rev)
    }
  }
}

pub fn do_field(f, i, rev) {
  let i = i * 2
  let j = i + 1
  let #(field, var) = f
  [
    h.span([exp_key([i, ..rev])], [text(field)]),
    h.span([], [text(": ")]),
    h.span([exp_key([j, ..rev])], [text(var)]),
  ]
}

pub fn do_destructured(fields, rev) {
  fields
  |> list.intersperse([h.span([], [text(", ")])])
  |> list.flatten
  |> list.append([h.span([exp_key(rev)], [text("}")])])
  |> list.append([h.span([exp_key(rev)], [text("{")])], _)
}

pub fn patterns(ps, rev) {
  list.index_map(ps, fn(p, i) { pattern(p, [i, ..rev]) })
  |> join_patterns()
}

pub fn join_patterns(ps) {
  ps
  |> list.intersperse([text(", ")])
  |> list.flatten
  |> list.append([text(")")])
  |> list.append([text("(")], _)
}

pub fn render_args(args, rev) {
  // 0 is the call
  let args = list.index_map(args, fn(a, i) { expression(a, [i + 1, ..rev]) })
  let assert [last, ..rest] = list.reverse(args)
  render_args_rev(last, rest)
}

pub fn render_args_e(args) {
  let assert [last, ..rest] = list.reverse(args)
  render_args_rev(last, rest)
}

fn render_args_rev(last, rest) {
  case frame.all_inline(rest) {
    Ok(spanss) ->
      list.fold(spanss, last, fn(tail, spans) {
        tail
        |> frame.prepend_spans([text(", ")], _)
        |> frame.prepend_spans(spans, _)
      })
    Error(Nil) -> {
      list.reverse([last, ..rest])
      |> list.map(frame.append_spans(_, [text(",")]))
      |> frame.to_fat_lines
      |> frame.Multiline([], _, [])
    }
  }
}

pub fn render_call(f, args) {
  let args =
    args
    |> frame.prepend_spans([text("(")], _)
    |> frame.append_spans([text(")")])

  case f {
    frame.Inline(fspans) -> frame.prepend_spans(fspans, args)
    frame.Statements(inner) -> {
      let f = frame.Multiline([text("{")], inner, [text("}")])
      frame.join(f, args)
    }
    frame.Multiline(_, _, _) -> frame.join(f, args)
  }
}

fn exp_key(rev) {
  a.attribute("data-rev", string.join(list.map(rev, int.to_string), ","))
}

pub fn expression(exp, rev) {
  case exp {
    e.Block(_, _, False) -> frame.Inline([text("{ ... }")])
    e.Block(assigns, tail, True) ->
      frame.Multiline(
        [h.span([], [text("{")])],
        frame.to_fat_lines(block_content(assigns, tail, rev)),
        [h.span([], [text("}")])],
      )
    e.Call(f, args) -> {
      let args = render_args(args, rev)
      let f = expression(f, [0, ..rev])
      render_call(f, args)
    }
    // defninetly multiline don't wrap in double curlies
    // e.Function(args, e.Block(assigns, tail)) ->
    // render_function(patterns(args), block_content(assigns, tail))
    // frame.Multiline(
    //   [h.span([], [text("("), patterns(args), text(") -> {")])],
    //   frame.to_fat_lines(block_content(assigns, tail)),
    //   [h.span([], [text("}")])],
    // )
    e.Function(args, body) -> {
      render_function(
        patterns(args, rev),
        expression(body, [list.length(args), ..rev]),
        rev,
      )
    }
    e.Vacant(_) ->
      frame.Inline([
        h.span([a.class("text-red-700"), exp_key(rev)], [text("Vacant")]),
      ])
    e.Variable(x) ->
      frame.Inline([h.span([a.class("text-gray-700"), exp_key(rev)], [text(x)])])
    e.Integer(v) ->
      frame.Inline([
        h.span([a.class("text-purple-2"), exp_key(rev)], [
          text(int.to_string(v)),
        ]),
      ])
    e.Binary(_) ->
      frame.Inline([
        h.span([a.class("text-orange-2"), exp_key(rev)], [
          text("binary is still to be rendered"),
        ]),
      ])

    e.String(v) ->
      frame.Inline([
        h.span([a.class("text-green-4"), exp_key(rev)], [
          text("\""),
          text(v),
          text("\""),
        ]),
      ])
    e.List(items, tail) -> {
      render_list(
        list.index_map(items, fn(item, i) { expression(item, [i, ..rev]) }),
        option.map(tail, expression(_, [list.length(items), ..rev])),
        rev,
      )
    }
    e.Record(fields, original) -> {
      let len = list.length(fields) * 2
      render_record(
        list.index_map(fields, fn(field, i) { render_field(field, i * 2, rev) }),
        option.map(original, expression(_, [len, ..rev])),
        rev,
      )
    }
    e.Select(from, label) ->
      expression(from, [0, ..rev])
      |> frame.append_spans([
        text("."),
        h.span([exp_key([1, ..rev])], [text(label)]),
      ])
    e.Tag(label) ->
      frame.Inline([
        h.span([a.class("text-blue-900"), exp_key(rev)], [text(label)]),
      ])
    e.Case(top, matches, otherwise) -> {
      let top = expression(top, [0, ..rev])
      let matches =
        list.index_map(matches, fn(match, i) {
          render_branch(match, [i + 1, ..rev])
        })
      let otherwise =
        option.map(otherwise, expression(_, [list.length(matches) + 1, ..rev]))
      render_case(top, matches, otherwise, rev)
    }
    e.Perform(label) ->
      frame.Inline([
        h.span([a.class("text-gray-700")], [text("perform ")]),
        h.span([a.class("text-blue-900"), exp_key(rev)], [text(label)]),
      ])
    e.Deep(label) ->
      frame.Inline([
        h.span([a.class("text-gray-700")], [text("handle ")]),
        h.span([a.class("text-blue-900"), exp_key(rev)], [text(label)]),
      ])
    e.Shallow(label) ->
      frame.Inline([
        h.span([a.class("text-gray-700")], [text("shallow ")]),
        h.span([a.class("text-blue-900"), exp_key(rev)], [text(label)]),
      ])

    e.Builtin(identifier) ->
      frame.Inline([
        h.span([a.class("text-orange-3"), exp_key(rev)], [
          text("!"),
          text(identifier),
        ]),
      ])
    e.Reference(identifier) ->
      case identifier {
        "@" <> rest -> {
          let assert [name, v, ..] = string.split(rest, ":")
          frame.Inline([
            h.span(
              [
                a.class("text-purple-800"),
                exp_key(rev),
                a.title("version = " <> v),
              ],
              [text("@" <> name)],
            ),
          ])
        }
        _ ->
          frame.Inline([
            h.span([a.class("text-gray-800"), exp_key(rev)], [text(identifier)]),
          ])
      }
  }
}

pub fn render_function(args, body, rev) {
  body
  // TODO handle spaces on wrapping
  |> frame.prepend_spans([h.span([exp_key(rev)], [text(" -> ")])], _)
  |> frame.prepend_spans(args, _)
  // |> frame.append_spans([text(" }")])
}

pub fn render_list(items, tail, rev) {
  let tail = case tail {
    Some(tail) -> [frame.prepend_spans([text("..")], tail)]
    None -> []
  }
  let items = list.append(items, tail)
  let items = frame.delimit(items, ", ")
  case frame.all_inline(items) {
    Ok(spans) ->
      frame.Inline([
        h.span(
          [exp_key(rev)],
          list.flatten([[text("[")], list.flatten(spans), [text("]")]]),
        ),
      ])
    Error(Nil) -> {
      let inner = frame.to_fat_lines(items)
      frame.Multiline([h.span([exp_key(rev)], [text("[")])], inner, [
        h.span([exp_key(rev)], [text("]")]),
      ])
    }
  }
}

pub fn render_record(fields, original, rev) {
  let original = case original {
    Some(original) -> [frame.prepend_spans([text("..")], original)]
    None -> []
  }
  let fields = list.append(fields, original)
  let fields = frame.delimit(fields, ", ")

  case frame.all_inline(fields) {
    Ok(spans) ->
      frame.Inline([
        h.span(
          [exp_key(rev)],
          list.flatten([[text("{")], list.flatten(spans), [text("}")]]),
        ),
      ])
    Error(Nil) -> {
      let inner = frame.to_fat_lines(fields)
      frame.Multiline([h.span([exp_key(rev)], [text("{")])], inner, [
        h.span([exp_key(rev)], [text("}")]),
      ])
    }
  }
}

pub fn render_field(field, i, rev) {
  let #(label, value) = field
  let value = expression(value, [i + 1, ..rev])
  frame.prepend_spans(
    [h.span([exp_key([i, ..rev])], [text(label), text(": ")])],
    value,
  )
}

pub fn do_render_field(field, rev) {
  let #(label, value) = field
  frame.prepend_spans(
    [h.span([], [h.span([exp_key(rev)], [text(label)]), text(": ")])],
    value,
  )
}

pub fn render_case(top, branches, otherwise, rev) {
  let spans = case top {
    frame.Inline(spans) -> spans
    _ -> {
      [text("some big case")]
    }
  }
  list.append(branches, case otherwise {
    Some(otherwise) -> [otherwise]
    None -> []
  })
  |> frame.to_fat_lines
  |> frame.Multiline([text(" {")], _, [text("}")])
  |> frame.prepend_spans(spans, _)
  |> frame.prepend_spans([h.span([exp_key(rev)], [text("match ")])], _)
}

pub fn render_branch(field, rev) {
  let #(label, value) = field
  let value = expression(value, [0, ..rev])
  frame.prepend_spans(
    [h.span([a.class("text-blue-700"), exp_key(rev)], [text(label), text(" ")])],
    value,
  )
}

// rev passed in here is rest of rev
fn render_break(break, inner, rev, is_expression) {
  case break {
    t.CallFn(args) -> render_call(inner, render_args(args, rev))
    t.CallArg(f, pre, post) -> {
      let self = list.length(pre) + 1
      let pre =
        list.index_map(pre, fn(arg, i) {
          expression(arg, [self - i - 1, ..rev])
        })
      let post =
        list.index_map(post, fn(arg, i) {
          expression(arg, [self + i + 1, ..rev])
        })
      let args = listx.gather_around(pre, inner, post)
      render_call(expression(f, [0, ..rev]), render_args_e(args))
    }
    t.Body(args) -> render_function(patterns(args, rev), inner, rev)
    t.ListItem(pre, post, tail) -> {
      let self = list.length(pre)
      let pre =
        list.index_map(pre, fn(item, i) {
          expression(item, [self - i - 1, ..rev])
        })
      let post =
        list.index_map(post, fn(item, i) {
          expression(item, [self + i + 1, ..rev])
        })
      let len = self + 1 + list.length(post)
      render_list(
        listx.gather_around(pre, inner, post),
        option.map(tail, expression(_, [len, ..rev])),
        rev,
      )
    }
    t.ListTail(items) ->
      render_list(
        list.index_map(items, fn(item, i) { expression(item, [i, ..rev]) }),
        Some(inner),
        rev,
      )
    t.RecordValue(l, pre, post, for) -> {
      let self = list.length(pre) * 2
      let pre =
        list.index_map(pre, fn(field, i) {
          render_field(field, self - i * 2 - 2, rev)
        })
      let post =
        list.index_map(post, fn(field, i) {
          render_field(field, self + i * 2 + 2, rev)
        })
      let inner = do_render_field(#(l, inner), [self, ..rev])
      let len = self + { 1 + list.length(post) } * 2
      let original = case for {
        t.Record -> None
        t.Overwrite(original) -> Some(expression(original, [len, ..rev]))
      }
      render_record(listx.gather_around(pre, inner, post), original, rev)
    }
    t.SelectValue(label) ->
      inner
      |> frame.append_spans([
        text("."),
        h.span([exp_key([1, ..rev])], [text(label)]),
      ])
    t.OverwriteTail(fields) -> {
      let fields =
        list.index_map(list.reverse(fields), fn(field, i) {
          render_field(field, i * 2, rev)
        })
      render_record(fields, Some(inner), rev)
    }
    t.BlockValue(p, pre, post, then) -> {
      let self = list.length(pre)
      let pre =
        list.index_map(pre, fn(a, i) { assign_pair(a, [self - i - 1, ..rev]) })
      let post =
        list.index_map(post, fn(a, i) { assign_pair(a, [self + 1 + i, ..rev]) })
      let assign = do_let([self, ..rev], pattern(p, [0, self, ..rev]), inner)
      let assignments = listx.gather_around(pre, assign, post)
      let len = self + 1 + list.length(post)
      case is_expression, then {
        False, e.Vacant(_) -> assignments
        _, _ -> list.append(assignments, [expression(then, [len, ..rev])])
      }
      |> frame.to_fat_lines()
      |> frame.Statements
    }
    t.BlockTail(assigns) -> {
      let lines =
        list.index_map(assigns, fn(a, i) { assign_pair(a, [i, ..rev]) })
        |> list.append([inner])
      frame.Statements(frame.to_fat_lines(lines))
    }
    t.CaseTop(matches, otherwise) -> {
      let matches =
        list.index_map(matches, fn(m, i) { render_branch(m, [i + 1, ..rev]) })
      let otherwise =
        option.map(otherwise, expression(_, [list.length(matches) + 1, ..rev]))
      render_case(inner, matches, otherwise, rev)
    }
    t.CaseMatch(top, label, pre, post, otherwise) -> {
      let top = expression(top, [0, ..rev])
      let self = list.length(pre) + 1
      let pre =
        list.index_map(pre, fn(branch, i) {
          render_branch(branch, [self - i - 1, ..rev])
        })
      let post =
        list.index_map(post, fn(branch, i) {
          render_branch(branch, [self + 1 + i, ..rev])
        })
      let branch =
        frame.prepend_spans(
          [
            h.span([a.class("text-blue-700"), exp_key([self, ..rev])], [
              text(label),
              text(" "),
            ]),
          ],
          inner,
        )
      let len = self + 1 + list.length(post)
      let otherwise = option.map(otherwise, expression(_, [len, ..rev]))

      render_case(top, listx.gather_around(pre, branch, post), otherwise, rev)
    }
    t.CaseTail(top, matches) -> {
      let top = expression(top, [0, ..rev])
      let matches =
        list.index_map(matches, fn(m, i) { render_branch(m, [i + 1, ..rev]) })
      render_case(top, matches, Some(inner), rev)
    }
  }
}

fn push_render(frame, zoom, is_expression) {
  case zoom {
    [] -> frame
    [break, ..rest] -> {
      let frame =
        render_break(
          break,
          frame,
          list.reverse(t.path_to_zoom(rest, [])),
          is_expression,
        )
      push_render(frame, rest, is_expression)
    }
  }
}

pub fn projection(zip, is_expression) -> element.Element(a) {
  let #(focus, zoom) = zip
  // This is NOT reversed because zoom works from inside out
  let rev = t.path_to_zoom(zoom, [])
  let rev = list.reverse(rev)
  let frame = case focus {
    t.Exp(e.Vacant(_)) ->
      highlight.frame(
        frame.Inline([
          // made as an input for copy paste
          h.input([
            exp_key(rev),
            a.placeholder("Vacant"),
            a.class("placeholder-red-700 w-14 outline-none bg-transparent"),
            a.id("highlighted"),
            a.style([#("caret-color", "transparent")]),
            // TODO does the paste event bubble
            // if works we need a paste with path location
            event.on("keydown", fn(event) {
              event.prevent_default(event)
              Error([])
            }),
          ]),
        ]),
      )
    t.Exp(exp) -> highlight.frame(expression(exp, rev))
    t.Assign(detail, value, pre, post, then) -> {
      let self = list.length(pre)
      let pre =
        list.index_map(pre, fn(a, i) { do_assign(a, [self - i - 1, ..rev]) })
      let post =
        list.index_map(post, fn(a, i) { do_assign(a, [self + 1 + i, ..rev]) })

      let assign = case detail {
        // get rid of assign statement then do_let goes on the outside
        t.AssignStatement(p) -> highlight.frame(assign(p, value, [self, ..rev]))
        t.AssignPattern(p) -> {
          let p = [highlight.spans(pattern(p, [0, self, ..rev]))]
          do_let([self, ..rev], p, expression(value, [1, self, ..rev]))
        }
        t.AssignField(label, var, pre, post) -> {
          // to the pattern
          let rev = [0, self, ..rev]
          let self = list.length(pre) * 2
          let spans = [
            highlight.spans([h.span([exp_key([self, ..rev])], [text(label)])]),
            h.span([], [text(": ")]),
            h.span([exp_key([self + 1, ..rev])], [text(var)]),
          ]
          let pre =
            list.index_map(pre, fn(f, i) { do_field(f, self - 2 - 2 * i, rev) })
          let post =
            list.index_map(post, fn(f, i) { do_field(f, self + 2 + 2 * i, rev) })
          let pattern =
            do_destructured(listx.gather_around(pre, spans, post), rev)
          do_let([self, ..rev], pattern, expression(value, [1, self, ..rev]))
        }
        t.AssignBind(label, var, pre, post) -> {
          let rev = [0, self, ..rev]
          let self = list.length(pre) * 2
          let spans = [
            h.span([exp_key([self, ..rev])], [text(label)]),
            h.span([], [text(": ")]),
            highlight.spans([h.span([exp_key(rev)], [text(var)])]),
          ]
          let pre =
            list.index_map(pre, fn(f, i) { do_field(f, self - 2 - 2 * i, rev) })
          let post =
            list.index_map(post, fn(f, i) { do_field(f, self + 2 + 2 * i, rev) })
          let pattern =
            do_destructured(listx.gather_around(pre, spans, post), rev)
          do_let([self, ..rev], pattern, expression(value, [1, ..rev]))
        }
      }
      let len = list.length(pre) + list.length(post) + 1

      let assignments = listx.gather_around(pre, assign, post)
      case is_expression, then {
        False, e.Vacant(_) -> assignments
        _, _ -> list.append(assignments, [expression(then, [len, ..rev])])
      }
      |> frame.to_fat_lines
      |> frame.Statements
    }
    t.FnParam(detail, pre, post, body) -> {
      let self = list.length(pre)
      let len = self + list.length(post) + 1
      let pre =
        list.index_map(pre, fn(p, i) { pattern(p, [self - 1 - i, ..rev]) })
      let post =
        list.index_map(post, fn(p, i) { pattern(p, [self + 1 + i, ..rev]) })
      let pattern = case detail {
        t.AssignStatement(p) -> [highlight.spans(pattern(p, [self, ..rev]))]
        t.AssignPattern(p) -> [highlight.spans(pattern(p, [self, ..rev]))]

        t.AssignField(label, var, pre, post) -> {
          let rev = [self, ..rev]
          let self = list.length(pre) * 2
          let spans = [
            highlight.spans([h.span([exp_key([self, ..rev])], [text(label)])]),
            h.span([], [text(": ")]),
            h.span([exp_key([self + 1, ..rev])], [text(var)]),
          ]
          let pre =
            list.index_map(pre, fn(f, i) { do_field(f, self - 2 - 2 * i, rev) })
          let post =
            list.index_map(post, fn(f, i) { do_field(f, self + 2 + 2 * i, rev) })
          do_destructured(listx.gather_around(pre, spans, post), rev)
        }
        t.AssignBind(label, var, pre, post) -> {
          let rev = [self, ..rev]
          let self = list.length(pre) * 2
          let spans = [
            h.span([exp_key([self, ..rev])], [text(label)]),
            h.span([], [text(": ")]),
            highlight.spans([h.span([exp_key(rev)], [text(var)])]),
          ]
          let pre =
            list.index_map(pre, fn(f, i) { do_field(f, self - 2 - 2 * i, rev) })
          let post =
            list.index_map(post, fn(f, i) { do_field(f, self + 2 + 2 * i, rev) })
          do_destructured(listx.gather_around(pre, spans, post), rev)
        }
      }
      let patterns = listx.gather_around(pre, pattern, post)
      let patterns = join_patterns(patterns)
      render_function(patterns, expression(body, [len, ..rev]), rev)
    }
    t.Label(label, value, pre, post, for) -> {
      let self = list.length(pre) * 2
      let len = self + { list.length(post) + 1 } * 2
      let value = expression(value, [self + 1, ..rev])
      let label = highlight.spans([text(label)])
      let field = frame.prepend_spans([label, text(": ")], value)

      let pre =
        list.index_map(pre, fn(field, i) {
          render_field(field, self - i * 2 - 2, rev)
        })
      let post =
        list.index_map(post, fn(field, i) {
          render_field(field, self + i * 2 + 2, rev)
        })
      let original = case for {
        t.Record -> None
        t.Overwrite(original) -> Some(expression(original, [len, ..rev]))
      }

      render_record(listx.gather_around(pre, field, post), original, rev)
    }
    t.Select(label, from) -> {
      let from = expression(from, rev)
      from
      |> frame.append_spans([
        highlight.spans([text("."), h.span([exp_key(rev)], [text(label)])]),
      ])
    }
    t.Match(top, label, value, pre, post, otherwise) -> {
      let self = list.length(pre) + 1
      let len = self + list.length(post) + 1
      let value = expression(value, [0, self, ..rev])
      let branch =
        frame.prepend_spans(
          [
            highlight.spans([h.span([a.class("text-blue-700")], [text(label)])]),
            text(" "),
          ],
          value,
        )
      let pre =
        list.index_map(pre, fn(branch, i) {
          render_branch(branch, [self - i - 1, ..rev])
        })
      let post =
        list.index_map(post, fn(branch, i) {
          render_branch(branch, [self + i + 1, ..rev])
        })
      render_case(
        expression(top, [0, ..rev]),
        listx.gather_around(pre, branch, post),
        option.map(otherwise, expression(_, [len, ..rev])),
        rev,
      )
    }
  }
  push_render(frame, zoom, is_expression)
  |> frame.to_fat_line
  // TO fat line is very similar to top function
}

fn do_assign(kv, rev) {
  let #(label, value) = kv
  assign(label, value, rev)
}
