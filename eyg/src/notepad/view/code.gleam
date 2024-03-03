import gleam/io
import gleam/dynamic
import gleam/int
import gleam/option.{None, Some}
import gleam/list
import lustre/attribute as a
import lustre/element/html as h
import lustre/element.{text}
import lustre/event
import morph/editable as e

pub fn assign(pattern, value) {
  do_assign(pattern, expression(value))
}

pub fn do_assign(pattern, exp) {
  let assignment = case pattern {
    e.Bind(var) -> [
      h.span([], [text("let ")]),
      h.span([a.class("text-blue-4")], [text(var)]),
      h.span([], [text(" = ")]),
    ]
    e.Destructure(bindings) -> {
      list.map(bindings, fn(b) {
        let #(label, var) = b
        [h.span([], [text(label), text(": "), text(var)])]
      })
      |> list.intersperse([h.span([], [text(", ")])])
      |> list.flatten
      |> list.append([h.span([], [text("let {")])], _)
      |> list.append([h.span([], [text("} = ")])])
    }
  }

  case exp {
    Single(spans) -> Single(list.append(assignment, spans))
    Multi(pre, inner, post) -> Multi(list.append(assignment, pre), inner, post)
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
pub fn to_fat_line(exp) {
  case exp {
    Single(spans) -> h.div([], spans)
    Multi(pre, inner, post) ->
      h.div([], [h.div([], pre), indent(inner), h.div([], post)])
  }
}

pub fn to_fat_lines(lines) {
  list.map(lines, to_fat_line)
}

pub fn top(code) {
  case code {
    e.Block(assigns, tail) -> block_content(assigns, tail)
    exp -> [expression(exp)]
  }
  |> to_fat_lines()
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
  case list.try_map(rest, assume_single) {
    Ok(spanss) ->
      list.fold(spanss, last, fn(tail, spans) {
        case tail {
          Single(old) -> Single(list.flatten([spans, [text(", ")], old]))
          Multi(pre, inner, post) ->
            Multi(list.flatten([spans, [text(", ")], pre]), inner, post)
        }
      })

    Error(Nil) -> {
      list.reverse([last, ..rest])
      |> list.map(postpend_span(_, text(",")))
      |> to_fat_lines
      |> Multi([], _, [])
    }
  }
}

pub fn render_call(f, args) {
  let assert Single(fspans) = f
  case args {
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

pub fn expression(exp) {
  case exp {
    e.Block(assigns, tail) ->
      Multi(
        [h.span([], [text("{")])],
        to_fat_lines(block_content(assigns, tail)),
        [h.span([], [text("}")])],
      )
    e.Call(f, args) -> {
      let args = render_args(args)
      let f = expression(f)
      render_call(f, args)
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
    e.Vacant -> Single([h.span([a.class("text-red-700")], [text("Vacant")])])
    e.Variable(x) -> Single([h.span([a.class("text-gray-700")], [text(x)])])
    e.Integer(v) ->
      Single([h.span([a.class("text-purple-2")], [text(int.to_string(v))])])
    e.String(v) ->
      Single([
        h.span([a.class("text-green-4")], [text("\""), text(v), text("\"")]),
      ])
    e.List([], tail) -> Single([text("[]")])
    e.List(items, tail) -> render_list(list.map(items, expression))
    e.Record(fields) -> render_record(list.map(fields, render_field))
    _ -> {
      io.debug(exp)
      panic as "exp"
    }
  }
}

pub fn render_list(ms) {
  ms
  |> list.map(to_list_item)
  |> Multi([text("[")], _, [text("]")])
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

pub fn all_single(ms) {
  list.try_map(ms, assume_single)
}

pub fn render_record(fields) {
  let fields = list.map(fields, append_spans(_, [text(", ")]))
  case all_single(fields) {
    Ok(spans) ->
      Single(list.flatten([[text("{")], list.flatten(spans), [text("}")]]))
  }
}

pub fn render_field(field) {
  let #(label, value) = field
  let value = expression(value)
  prepend_spans([h.span([], [text(label), text(": ")])], value)
}

pub fn prepend_spans(new, m) {
  case m {
    Single(spans) -> Single(list.append(new, spans))
    Multi(pre, inner, post) -> Multi(list.append(new, pre), inner, post)
  }
}

pub fn append_spans(m, new) {
  case m {
    Single(spans) -> Single(list.append(spans, new))
    Multi(pre, inner, post) -> Multi(list.append(pre, new), inner, post)
  }
}
