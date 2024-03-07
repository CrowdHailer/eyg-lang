import gleam/io
import gleam/int
import gleam/option.{None, Some}
import gleam/list
import lustre/attribute as a
import lustre/element/html as h
import lustre/element.{text}
import morph/editable as e
import morph/transform as t
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
    e.List(items, tail) ->
      render_list(list.map(items, expression), option.map(tail, expression))
    e.Record(fields, original) ->
      render_record(
        list.map(fields, render_field),
        option.map(original, expression),
      )
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
    e.Builtin(identifier) ->
      frame.Inline([
        h.span([a.class("text-orange-3")], [text("!"), text(identifier)]),
      ])
    _ -> {
      io.debug(exp)
      panic as "exp"
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

fn delimit(frames, delimiter) {
  case list.reverse(frames) {
    [] -> []
    [last, ..rest] -> {
      let rest = list.map(rest, frame.append_spans(_, [text(delimiter)]))
      list.reverse([last, ..rest])
    }
  }
}

pub fn render_list(items, tail) {
  let tail = case tail {
    Some(tail) -> [frame.prepend_spans([text("..")], tail)]
    None -> []
  }
  let items = list.append(items, tail)
  let items = delimit(items, ", ")
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
  let fields = delimit(fields, ", ")

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
  frame.prepend_spans(
    [h.span([a.class("text-blue-700")], [text(label), text(" ")])],
    value,
  )
}

pub fn render_break(break, inner) {
  case break {
    t.CallFn(args) -> render_call(inner, render_args(args))
    t.CallArg(f, pre, post) -> {
      let pre = list.map(pre, expression)
      let post = list.map(post, expression)
      let args = t.gather_around(pre, inner, post)
      render_call(expression(f), render_args_e(args))
    }
    t.Body(args) -> render_function(patterns(args), inner)
    t.ListItem(pre, post, tail) -> {
      let pre = list.map(pre, expression)
      let post = list.map(post, expression)
      render_list(
        t.gather_around(pre, inner, post),
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
      render_record(t.gather_around(pre, inner, post), original)
    }
    t.OverwriteTail(fields) -> {
      let fields = list.map(list.reverse(fields), render_field)
      render_record(fields, Some(inner))
    }
    t.BlockValue(p, pre, post, then) -> {
      let pre = list.map(pre, assign_pair)
      let post = list.map(post, assign_pair)
      let assign = do_let(pattern(p), inner)
      t.gather_around(pre, assign, post)
      |> list.append([expression(then)])
      |> frame.to_fat_lines()
      |> frame.Multiline([text("{")], _, [text("}")])
    }

    t.BlockTail(assigns) -> {
      let lines =
        list.map(assigns, assign_pair)
        |> list.append([inner])
      // TODO remove work out tail
      // case rest {
      //   // escape early to not wrap block
      //   [] ->
      // }
      frame.Multiline([text("{")], frame.to_fat_lines(lines), [text("}")])
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
      let branch = frame.prepend_spans([text(label), text(" ")], inner)
      let otherwise = option.map(otherwise, expression)

      render_case(top, t.gather_around(pre, branch, post), otherwise)
    }
    t.CaseTail(top, matches) -> {
      let top = expression(top)
      let matches = list.map(matches, render_branch)
      render_case(top, matches, Some(inner))
    }
  }
  // _ -> {
  //   io.debug(break)
  //   panic as "bad push"
  // }
}
