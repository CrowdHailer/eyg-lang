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
import notepad/view/frame

pub fn do_let(pattern, value) {
  let assignment = list.flatten([[text("let ")], pattern, [text(" = ")]])
  frame.prepend_spans(assignment, value)
}

pub fn assign(p, value) {
  do_let(pattern(p), expression(value))
}

// is for unwrapped block
pub fn top(code) {
  case code {
    e.Block(assigns, tail) -> block_content(assigns, tail)
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
  let assert frame.Inline(fspans) = f
  args
  |> frame.prepend_spans([text("(")], _)
  |> frame.prepend_spans(fspans, _)
  |> frame.append_spans([text(")")])
}

pub fn expression(exp) {
  case exp {
    e.Block(assigns, tail) ->
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
    e.Function(args, e.Block(assigns, tail)) ->
      frame.Multiline(
        [h.span([], [text("("), text("arg"), text(") -> {")])],
        frame.to_fat_lines(block_content(assigns, tail)),
        [h.span([], [text("}")])],
      )
    e.Function(args, body) -> {
      render_function(patterns(args), expression(body))
    }
    e.Vacant ->
      frame.Inline([h.span([a.class("text-red-700")], [text("Vacant")])])
    e.Variable(x) ->
      frame.Inline([h.span([a.class("text-gray-700")], [text(x)])])
    e.Integer(v) ->
      frame.Inline([
        h.span([a.class("text-purple-2")], [text(int.to_string(v))]),
      ])
    e.String(v) ->
      frame.Inline([
        h.span([a.class("text-green-4")], [text("\""), text(v), text("\"")]),
      ])
    e.List([], tail) -> frame.Inline([text("[]")])
    e.List(items, tail) -> render_list(list.map(items, expression))
    e.Record(fields) -> render_record(list.map(fields, render_field))
    e.Tag(label) ->
      frame.Inline([h.span([a.class("text-blue-900")], [text(label)])])
    _ -> {
      io.debug(exp)
      panic as "exp"
    }
  }
}

pub fn render_function(args, body) {
  body
  // TODO handle spaces on wrapping
  |> frame.prepend_spans([text(" -> { ")], _)
  |> frame.prepend_spans(args, _)
  |> frame.append_spans([text(" }")])
}

pub fn render_list(ms) {
  ms
  |> list.map(to_list_item)
  |> frame.Multiline([text("[")], _, [text("]")])
}

fn to_list_item(f) {
  f
  |> frame.append_spans([text(",")])
  |> frame.to_fat_line
}

pub fn render_record(fields) {
  let fields = list.map(fields, frame.append_spans(_, [text(", ")]))
  case frame.all_inline(fields) {
    Ok(spans) ->
      frame.Inline(
        list.flatten([[text("{")], list.flatten(spans), [text("}")]]),
      )
  }
}

pub fn render_field(field) {
  let #(label, value) = field
  let value = expression(value)
  frame.prepend_spans([h.span([], [text(label), text(": ")])], value)
}

pub fn render_case(top, branches, otherwise) {
  let frame.Inline(spans) = top
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
  let x =
    frame.prepend_spans(
      [h.span([a.class("text-blue-700")], [text(label)])],
      value,
    )
  case x {
    frame.Inline(spans) -> frame.Multiline([], [h.div([], spans)], [])
    frame -> frame
  }
}
