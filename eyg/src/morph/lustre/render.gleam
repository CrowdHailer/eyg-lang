import gleam/int
import gleam/io
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

pub fn do_let(pattern, value) {
  let assignment = list.flatten([[text("let ")], pattern, [text(" = ")]])
  frame.prepend_spans(assignment, value)
}

pub fn assign(p, value) {
  do_let(pattern(p), expression(value))
}

pub fn assigns(a) {
  list.map(a, assign_pair)
  |> frame.to_fat_lines()
}

// ignore tail vacant will need for spotless history
pub fn statements(code) {
  case code {
    e.Block(assigns, e.Vacant(_), _) -> list.map(assigns, assign_pair)
    e.Block(assigns, tail, _) -> block_content(assigns, tail)
    exp -> [expression(exp)]
  }
  |> frame.to_fat_lines()
}

// is for unwrapped block
pub fn top(code) {
  case code {
    e.Block(assigns, tail, _) -> block_content(assigns, tail)
    exp -> [expression(exp)]
  }
  |> frame.to_fat_lines()
}

fn block_content(assigns, tail) {
  list.map(assigns, assign_pair)
  |> list.append([expression(tail)])
}

fn assign_pair(kv) {
  let #(label, value) = kv
  assign(label, value)
}

pub fn pattern(p) {
  case p {
    e.Bind(x) -> [h.span([], [text(x)])]
    e.Destructure(fields) -> {
      list.map(fields, do_field)
      |> do_destructured
    }
  }
}

pub fn do_field(f) {
  let #(field, var) = f
  [h.span([], [text(field)]), h.span([], [text(": ")]), h.span([], [text(var)])]
}

pub fn do_destructured(fields) {
  fields
  |> list.intersperse([h.span([], [text(", ")])])
  |> list.flatten
  |> list.append([text("}")])
  |> list.append([text("{")], _)
}

pub fn patterns(ps) {
  list.map(ps, pattern)
  |> join_patterns()
}

pub fn join_patterns(ps) {
  ps
  |> list.intersperse([text(", ")])
  |> list.flatten
  |> list.append([text(")")])
  |> list.append([text("(")], _)
}

pub fn render_args(args) {
  let assert [last, ..rest] = list.reverse(args)
  let last = expression(last)
  let rest = list.map(rest, expression)
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

pub fn expression(exp) {
  case exp {
    e.Block(_, _, False) -> frame.Inline([text("{ ... }")])
    e.Block(assigns, tail, True) ->
      frame.Multiline(
        [h.span([], [text("{")])],
        frame.to_fat_lines(block_content(assigns, tail)),
        [h.span([], [text("}")])],
      )
    e.Call(f, args) -> {
      let args = render_args(args)
      let f = expression(f)
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
      render_function(patterns(args), expression(body))
    }
    e.Vacant(_) ->
      frame.Inline([h.span([a.class("text-red-700")], [text("Vacant")])])
    e.Variable(x) ->
      frame.Inline([h.span([a.class("text-gray-700")], [text(x)])])
    e.Integer(v) ->
      frame.Inline([
        h.span([a.class("text-purple-2")], [text(int.to_string(v))]),
      ])
    e.Binary(_) ->
      frame.Inline([
        h.span([a.class("text-orange-2")], [
          text("binary is still to be rendered"),
        ]),
      ])

    e.String(v) ->
      frame.Inline([
        h.span([a.class("text-green-4")], [text("\""), text(v), text("\"")]),
      ])
    e.List(items, tail) ->
      render_list(list.map(items, expression), option.map(tail, expression))
    e.Record(fields, original) ->
      render_record(
        list.map(fields, render_field),
        option.map(original, expression),
      )
    e.Select(from, label) ->
      expression(from)
      |> frame.append_spans([text("."), text(label)])
    e.Tag(label) ->
      frame.Inline([h.span([a.class("text-blue-900")], [text(label)])])
    e.Case(top, matches, otherwise) -> {
      let top = expression(top)
      let matches = list.map(matches, render_branch)
      let otherwise = option.map(otherwise, expression)
      render_case(top, matches, otherwise)
    }
    e.Perform(label) ->
      frame.Inline([
        h.span([a.class("text-gray-700")], [text("perform ")]),
        h.span([a.class("text-blue-900")], [text(label)]),
      ])
    e.Deep(label) ->
      frame.Inline([
        h.span([a.class("text-gray-700")], [text("handle ")]),
        h.span([a.class("text-blue-900")], [text(label)]),
      ])
    e.Shallow(label) ->
      frame.Inline([
        h.span([a.class("text-gray-700")], [text("shallow ")]),
        h.span([a.class("text-blue-900")], [text(label)]),
      ])

    e.Builtin(identifier) ->
      frame.Inline([
        h.span([a.class("text-orange-3")], [text("!"), text(identifier)]),
      ])
    e.Reference(identifier) ->
      case identifier {
        "@" <> rest -> {
          let assert [name, v, ..] = string.split(rest, ":")
          frame.Inline([
            h.span([a.class("text-purple-800"), a.title("version = " <> v)], [
              text("@" <> name),
            ]),
          ])
        }
        _ ->
          frame.Inline([h.span([a.class("text-gray-800")], [text(identifier)])])
      }
  }
}

pub fn render_function(args, body) {
  body
  // TODO handle spaces on wrapping
  |> frame.prepend_spans([text(" -> ")], _)
  |> frame.prepend_spans(args, _)
  // |> frame.append_spans([text(" }")])
}

pub fn render_list(items, tail) {
  let tail = case tail {
    Some(tail) -> [frame.prepend_spans([text("..")], tail)]
    None -> []
  }
  let items = list.append(items, tail)
  let items = frame.delimit(items, ", ")
  case frame.all_inline(items) {
    Ok(spans) ->
      frame.Inline(
        list.flatten([[text("[")], list.flatten(spans), [text("]")]]),
      )
    Error(Nil) -> {
      let inner = frame.to_fat_lines(items)
      frame.Multiline([text("[")], inner, [text("]")])
    }
  }
}

pub fn render_record(fields, original) {
  let original = case original {
    Some(original) -> [frame.prepend_spans([text("..")], original)]
    None -> []
  }
  let fields = list.append(fields, original)
  let fields = frame.delimit(fields, ", ")

  case frame.all_inline(fields) {
    Ok(spans) ->
      frame.Inline(
        list.flatten([[text("{")], list.flatten(spans), [text("}")]]),
      )
    Error(Nil) -> {
      let inner = frame.to_fat_lines(fields)
      frame.Multiline([text("{")], inner, [text("}")])
    }
  }
}

pub fn render_field(field) {
  let #(label, value) = field
  let value = expression(value)
  frame.prepend_spans([h.span([], [text(label), text(": ")])], value)
}

pub fn do_render_field(field) {
  let #(label, value) = field
  frame.prepend_spans([h.span([], [text(label), text(": ")])], value)
}

pub fn render_case(top, branches, otherwise) {
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
  |> frame.prepend_spans([text("match ")], _)
}

pub fn render_branch(field) {
  let #(label, value) = field
  let value = expression(value)
  frame.prepend_spans(
    [h.span([a.class("text-blue-700")], [text(label), text(" ")])],
    value,
  )
}

fn render_break(break, inner, is_expression) {
  case break {
    t.CallFn(args) -> render_call(inner, render_args(args))
    t.CallArg(f, pre, post) -> {
      let pre = list.map(pre, expression)
      let post = list.map(post, expression)
      let args = listx.gather_around(pre, inner, post)
      render_call(expression(f), render_args_e(args))
    }
    t.Body(args) -> render_function(patterns(args), inner)
    t.ListItem(pre, post, tail) -> {
      let pre = list.map(pre, expression)
      let post = list.map(post, expression)
      render_list(
        listx.gather_around(pre, inner, post),
        option.map(tail, expression),
      )
    }
    t.ListTail(items) -> render_list(list.map(items, expression), Some(inner))
    t.RecordValue(l, pre, post, for) -> {
      let pre = list.map(pre, render_field)
      let post = list.map(post, render_field)
      let inner = do_render_field(#(l, inner))
      let original = case for {
        t.Record -> None
        t.Overwrite(original) -> Some(expression(original))
      }
      render_record(listx.gather_around(pre, inner, post), original)
    }
    t.SelectValue(label) ->
      inner
      |> frame.append_spans([text("."), text(label)])
    t.OverwriteTail(fields) -> {
      let fields = list.map(list.reverse(fields), render_field)
      render_record(fields, Some(inner))
    }
    t.BlockValue(p, pre, post, then) -> {
      let pre = list.map(pre, assign_pair)
      let post = list.map(post, assign_pair)
      let assign = do_let(pattern(p), inner)
      let assignments = listx.gather_around(pre, assign, post)
      case is_expression, then {
        False, e.Vacant(_) -> assignments
        _, _ -> list.append(assignments, [expression(then)])
      }
      |> frame.to_fat_lines()
      |> frame.Statements
    }
    t.BlockTail(assigns) -> {
      let lines =
        list.map(assigns, assign_pair)
        |> list.append([inner])
      frame.Statements(frame.to_fat_lines(lines))
    }
    t.CaseTop(matches, otherwise) -> {
      let matches = list.map(matches, render_branch)
      let otherwise = option.map(otherwise, expression)
      render_case(inner, matches, otherwise)
    }
    t.CaseMatch(top, label, pre, post, otherwise) -> {
      let top = expression(top)
      let pre = list.map(pre, render_branch)
      let post = list.map(post, render_branch)
      let branch =
        frame.prepend_spans(
          [h.span([a.class("text-blue-700")], [text(label), text(" ")])],
          inner,
        )
      let otherwise = option.map(otherwise, expression)

      render_case(top, listx.gather_around(pre, branch, post), otherwise)
    }
    t.CaseTail(top, matches) -> {
      let top = expression(top)
      let matches = list.map(matches, render_branch)
      render_case(top, matches, Some(inner))
    }
  }
}

fn push_render(frame, zoom, is_expression) {
  case zoom {
    [] -> frame
    [break, ..rest] -> {
      let frame = render_break(break, frame, is_expression)
      push_render(frame, rest, is_expression)
    }
  }
}

pub fn projection(zip, is_expression) -> element.Element(a) {
  let #(focus, zoom) = zip
  let frame = case focus {
    t.Exp(e.Vacant(_)) ->
      highlight.frame(
        frame.Inline([
          // made as an input for copy paste
          h.input([
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
    t.Exp(exp) -> highlight.frame(expression(exp))
    t.Assign(detail, value, pre, post, then) -> {
      let pre = list.map(pre, do_assign)
      let post = list.map(post, do_assign)

      let assign = case detail {
        // get rid of assign statement then do_let goes on the outside
        t.AssignStatement(p) -> highlight.frame(assign(p, value))
        t.AssignPattern(p) -> {
          let p = [highlight.spans(pattern(p))]
          do_let(p, expression(value))
        }
        t.AssignField(label, var, pre, post) -> {
          let spans = [
            highlight.spans([text(label)]),
            h.span([], [text(": ")]),
            h.span([], [text(var)]),
          ]
          let pre = list.map(pre, do_field)
          let post = list.map(post, do_field)
          let pattern = do_destructured(listx.gather_around(pre, spans, post))
          do_let(pattern, expression(value))
        }
        t.AssignBind(label, var, pre, post) -> {
          let spans = [
            h.span([], [text(label)]),
            h.span([], [text(": ")]),
            highlight.spans([text(var)]),
          ]
          let pre = list.map(pre, do_field)
          let post = list.map(post, do_field)
          let pattern = do_destructured(listx.gather_around(pre, spans, post))
          do_let(pattern, expression(value))
        }
      }

      let assignments = listx.gather_around(pre, assign, post)
      case is_expression, then {
        False, e.Vacant(_) -> assignments
        _, _ -> list.append(assignments, [expression(then)])
      }
      |> frame.to_fat_lines
      |> frame.Statements
    }
    t.FnParam(detail, pre, post, body) -> {
      let pre = list.map(pre, pattern)
      let post = list.map(post, pattern)
      let pattern = case detail {
        t.AssignStatement(p) -> [highlight.spans(pattern(p))]
        t.AssignPattern(p) -> [highlight.spans(pattern(p))]

        t.AssignField(label, var, pre, post) -> {
          let spans = [
            highlight.spans([text(label)]),
            h.span([], [text(": ")]),
            h.span([], [text(var)]),
          ]
          let pre = list.map(pre, do_field)
          let post = list.map(post, do_field)
          do_destructured(listx.gather_around(pre, spans, post))
        }
        t.AssignBind(label, var, pre, post) -> {
          let spans = [
            h.span([], [text(label)]),
            h.span([], [text(": ")]),
            highlight.spans([text(var)]),
          ]
          let pre = list.map(pre, do_field)
          let post = list.map(post, do_field)
          do_destructured(listx.gather_around(pre, spans, post))
        }
      }
      let patterns = listx.gather_around(pre, pattern, post)
      let patterns = join_patterns(patterns)
      render_function(patterns, expression(body))
    }
    t.Label(label, value, pre, post, for) -> {
      let value = expression(value)
      let label = highlight.spans([text(label)])
      let field = frame.prepend_spans([label, text(": ")], value)

      let pre = list.map(pre, render_field)
      let post = list.map(post, render_field)
      let original = case for {
        t.Record -> None
        t.Overwrite(original) -> Some(expression(original))
      }

      render_record(listx.gather_around(pre, field, post), original)
    }
    t.Select(label, from) -> {
      let from = expression(from)
      from
      |> frame.append_spans([highlight.spans([text("."), text(label)])])
    }
    t.Match(top, label, value, pre, post, otherwise) -> {
      let value = expression(value)
      let branch =
        frame.prepend_spans(
          [
            highlight.spans([h.span([a.class("text-blue-700")], [text(label)])]),
            text(" "),
          ],
          value,
        )
      let pre = list.map(pre, render_branch)
      let post = list.map(post, render_branch)
      render_case(
        expression(top),
        listx.gather_around(pre, branch, post),
        option.map(otherwise, expression),
      )
    }
  }
  push_render(frame, zoom, is_expression)
  |> frame.to_fat_line
  // TO fat line is very similar to top function
}

fn do_assign(kv) {
  let #(label, value) = kv
  assign(label, value)
}
