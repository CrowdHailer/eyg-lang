// up to 91% of time is joining lists
import eyg/analysis/jm/tree
import eyg/analysis/jm/type_ as t
import eyg/ir/tree as ir
import gleam/dict
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import gleam/stringx

// reuse aterlier type
import easel/location.{type Location, Location}
import eyg/editor/v1/view/type_

pub type Style {
  Default
  Keyword
  Missing
  Hole
  Integer
  String
  Label
  Effect
  Builtin
  Reference
}

pub type Rendered =
  #(String, List(Int), Int, Style, Bool)

pub fn print(source, selection, always, analysis: Option(tree.State)) {
  let loc = Location([], selection, always)
  let #(acc, info) = do_print(source, loc, "\n", [], dict.new(), analysis)
  #(list.reverse(acc), info)
}

pub fn type_at(path, analysis) {
  case analysis {
    Some(analysis) -> {
      let #(_sub, _next, types) = analysis
      let assert Ok(t) = dict.get(types, list.reverse(path))
      Some(t)
    }
    None -> None
  }
}

fn is_error(path, analysis) {
  case type_at(path, analysis) {
    Some(t) -> result.is_error(t)
    None -> False
  }
}

fn do_print(source, loc: Location, br, acc, info, analysis) {
  let err = is_error(loc.path, analysis)
  let #(exp, _) = source
  case exp {
    ir.Lambda(param, body) -> {
      let #(acc, info) =
        print_with_offset(param, loc, Default, err, acc, info, analysis)
      let acc = print_keyword(" -> ", loc, acc, err)
      print_block(body, location.child(loc, 0), br, acc, info, analysis)
    }
    ir.Apply(#(ir.Select(label), _), from) -> {
      let #(acc, info) =
        print_block(from, location.child(loc, 1), br, acc, info, analysis)
      let info = dict.insert(info, path_to_string(loc.path), list.length(acc))
      let acc = print_keyword(".", loc, acc, err)
      print_with_offset(
        label,
        location.child(loc, 0),
        Default,
        err,
        acc,
        info,
        analysis,
      )
    }
    ir.Apply(#(ir.Apply(#(ir.Cons, _), item), _), tail) -> {
      let info = dict.insert(info, path_to_string(loc.path), list.length(acc))
      let acc = print_keyword("[", loc, acc, err)
      let #(acc, info) =
        print_block(
          item,
          location.child(location.child(loc, 0), 1),
          br,
          acc,
          info,
          analysis,
        )
      print_tail(tail, location.child(loc, 1), br, acc, info, analysis)
    }
    // It works using both here because a record should always end in empty
    // and overwrite always a variable
    ir.Apply(#(ir.Apply(#(ir.Extend(label), _), item), _), tail)
    | ir.Apply(#(ir.Apply(#(ir.Overwrite(label), _), item), _), tail) -> {
      // let info = dict.insert(info, path_to_string(loc.path), list.length(acc))
      let acc = print_keyword("{", loc, acc, err)
      let #(acc, info) =
        print_with_offset(label, loc, Label, err, acc, info, analysis)
      let acc = print_keyword(": ", loc, acc, err)
      let #(acc, info) =
        print_block(
          item,
          location.child(location.child(loc, 0), 1),
          br,
          acc,
          info,
          analysis,
        )
      print_extend(tail, location.child(loc, 1), br, acc, info, analysis)
    }
    ir.Apply(#(ir.Apply(#(ir.Case(label), _), item), _), tail) -> {
      let acc = print_keyword("match {", loc, acc, err)
      let br_inner = string.append(br, "  ")
      let acc = print_keyword(br_inner, loc, acc, err)
      let #(acc, info) =
        print_with_offset(label, loc, Label, err, acc, info, analysis)
      let acc = print_keyword(" ", loc, acc, err)
      let #(acc, info) =
        print_block(
          item,
          location.child(location.child(loc, 0), 1),
          br_inner,
          acc,
          info,
          analysis,
        )
      print_match(
        tail,
        location.child(loc, 1),
        br,
        br_inner,
        acc,
        info,
        analysis,
      )
    }
    ir.Apply(func, arg) -> {
      let #(acc, info) =
        print_block(func, location.child(loc, 0), br, acc, info, analysis)
      let info = dict.insert(info, path_to_string(loc.path), list.length(acc))

      let acc = print_keyword("(", loc, acc, err)
      let #(acc, info) =
        print_block(arg, location.child(loc, 1), br, acc, info, analysis)

      let acc = print_keyword(")", loc, acc, err)
      #(acc, info)
    }
    ir.Let(label, value, then) -> {
      let acc = print_keyword("let ", loc, acc, err)
      let #(acc, info) =
        print_with_offset(label, loc, Default, err, acc, info, analysis)
      let acc = print_keyword(" = ", loc, acc, err)
      let #(acc, info) =
        print_block(value, location.child(loc, 0), br, acc, info, analysis)
      let acc = print_keyword(br, loc, acc, err)
      do_print(then, location.child(loc, 1), br, acc, info, analysis)
    }
    ir.Variable(label) ->
      print_with_offset(label, loc, Default, err, acc, info, analysis)
    ir.Vacant -> {
      let content = case analysis {
        Some(#(sub, _next, types)) ->
          case dict.get(types, list.reverse(loc.path)) {
            Error(Nil) -> "todo"
            Ok(inferred) ->
              case inferred {
                Ok(t) -> {
                  let t = t.resolve(t, sub)
                  type_.render_type(t)
                }

                Error(#(r, t1, t2)) -> type_.render_failure(r, t1, t2)
              }
          }
        None -> "todo"
      }
      print_with_offset(content, loc, Hole, err, acc, info, analysis)
    }
    // TODO fix this acc needs to look like string
    ir.Binary(value) ->
      print_with_offset(
        print_bit_string(value),
        loc,
        Integer,
        err,
        acc,
        info,
        analysis,
      )
    ir.Integer(value) ->
      print_with_offset(
        int.to_string(value),
        loc,
        Integer,
        err,
        acc,
        info,
        analysis,
      )
    ir.String(value) -> {
      let acc = [#("\"", loc.path, -1, String, err), ..acc]
      // Maybe I don't need to append " if looking left
      // Dont escape html here as messes up index's when looking up element
      print_with_offset(
        string.append(value, "\""),
        loc,
        String,
        err,
        acc,
        info,
        analysis,
      )
    }
    ir.Tail -> {
      let info =
        dict.insert(info, path_to_string(loc.path), list.length(acc) + 1)
      let acc = print_keyword("[]", loc, acc, err)
      #(acc, info)
    }
    ir.Cons -> {
      let info = dict.insert(info, path_to_string(loc.path), list.length(acc))
      let acc = print_keyword("cons", loc, acc, err)
      #(acc, info)
    }
    ir.Empty -> {
      let info =
        dict.insert(info, path_to_string(loc.path), list.length(acc) + 1)
      let acc = print_keyword("{}", loc, acc, err)
      #(acc, info)
    }
    ir.Extend(label) -> {
      let acc = [#("+", loc.path, -1, Label, err), ..acc]
      print_with_offset(label, loc, Label, err, acc, info, analysis)
    }
    ir.Select(label) -> {
      let acc = [#(".", loc.path, -1, Label, err), ..acc]
      print_with_offset(label, loc, Label, err, acc, info, analysis)
    }
    ir.Overwrite(label) -> {
      let acc = [#("=", loc.path, -1, Label, err), ..acc]
      print_with_offset(label, loc, Label, err, acc, info, analysis)
    }
    ir.Tag(label) -> {
      // The idea was marking something as a tag
      // let acc = [#("=", loc.path, -1, Label), ..acc]
      print_with_offset(label, loc, Label, err, acc, info, analysis)
    }
    ir.Case(label) -> {
      let acc = [#("|", loc.path, -1, Label, err), ..acc]
      print_with_offset(label, loc, Label, err, acc, info, analysis)
    }
    ir.NoCases -> {
      let info = dict.insert(info, path_to_string(loc.path), list.length(acc))
      let acc = print_keyword("----", loc, acc, err)
      #(acc, info)
    }
    ir.Perform(label) -> {
      let acc = print_keyword("perform ", loc, acc, err)
      print_with_offset(label, loc, Effect, err, acc, info, analysis)
    }
    ir.Handle(label) -> {
      let acc = print_keyword("handle ", loc, acc, err)
      print_with_offset(label, loc, Effect, err, acc, info, analysis)
    }
    ir.Builtin(value) ->
      print_with_offset(value, loc, Builtin, err, acc, info, analysis)
    ir.Reference(value) ->
      print_with_offset(value, loc, Reference, err, acc, info, analysis)
    ir.Release(package, release, _id) -> {
      // TODO real id
      let value = "@" <> package <> ":" <> int.to_string(release)
      print_with_offset(value, loc, Reference, err, acc, info, analysis)
    }
  }
}

pub fn print_bit_string(value) {
  bit_string_to_integers(value, [])
  |> list.map(int.to_string)
  |> string.join(" ")
  |> string.append(">")
  |> string.append("<", _)
}

fn bit_string_to_integers(value, acc) {
  case value {
    <<byte, rest:bytes>> -> bit_string_to_integers(rest, [byte, ..acc])
    _ -> list.reverse(acc)
  }
}

fn print_block(source, loc: Location, br, acc, info, analysis) {
  let err = is_error(loc.path, analysis)
  let #(exp, _meta) = source
  case exp {
    ir.Let(_, _, _) -> {
      case location.open(loc) {
        True -> {
          let br_inner = string.append(br, "  ")
          let acc = print_keyword(string.append("{", br_inner), loc, acc, err)
          let #(acc, info) =
            do_print(source, loc, br_inner, acc, info, analysis)
          let acc = print_keyword(string.append(br, "}"), loc, acc, err)
          #(acc, info)
        }
        False -> {
          let info =
            dict.insert(info, path_to_string(loc.path), list.length(acc))
          let acc = print_keyword("{ ... }", loc, acc, err)
          #(acc, info)
        }
      }
    }
    _ -> do_print(source, loc, br, acc, info, analysis)
  }
}

fn print_tail(source, loc, br, acc, info, analysis) {
  let err = is_error(loc.path, analysis)
  let #(exp, _meta) = source

  case exp {
    ir.Tail -> {
      let info = dict.insert(info, path_to_string(loc.path), list.length(acc))
      let acc = print_keyword("]", loc, acc, err)
      #(acc, info)
    }
    ir.Apply(#(ir.Apply(#(ir.Cons, _), item), _), tail) -> {
      let info = dict.insert(info, path_to_string(loc.path), list.length(acc))
      let acc = print_keyword(", ", loc, acc, err)
      let #(acc, info) =
        print_block(
          item,
          location.child(location.child(loc, 0), 1),
          br,
          acc,
          info,
          analysis,
        )
      print_tail(tail, location.child(loc, 1), br, acc, info, analysis)
    }
    _ -> {
      let info = dict.insert(info, path_to_string(loc.path), list.length(acc))
      let acc = print_keyword(", ..", loc, acc, err)
      let #(acc, info) = print_block(source, loc, br, acc, info, analysis)
      let acc = print_keyword("]", loc, acc, err)
      #(acc, info)
    }
  }
}

fn print_extend(source, loc, br, acc, info, analysis) {
  let err = is_error(loc.path, analysis)
  let #(exp, _meta) = source
  case exp {
    ir.Empty -> {
      let info = dict.insert(info, path_to_string(loc.path), list.length(acc))
      let acc = print_keyword("}", loc, acc, err)
      #(acc, info)
    }
    ir.Apply(#(ir.Apply(#(ir.Extend(label), _), item), _), tail)
    | ir.Apply(#(ir.Apply(#(ir.Overwrite(label), _), item), _), tail) -> {
      let info = dict.insert(info, path_to_string(loc.path), list.length(acc))
      let acc = print_keyword(", ", loc, acc, err)
      let #(acc, info) =
        print_with_offset(label, loc, Label, err, acc, info, analysis)
      let acc = print_keyword(": ", loc, acc, err)
      let #(acc, info) =
        print_block(
          item,
          location.child(location.child(loc, 0), 1),
          br,
          acc,
          info,
          analysis,
        )
      print_extend(tail, location.child(loc, 1), br, acc, info, analysis)
    }
    _ -> {
      let info = dict.insert(info, path_to_string(loc.path), list.length(acc))
      let acc = print_keyword(", ..", loc, acc, err)
      let #(acc, info) = print_block(source, loc, br, acc, info, analysis)
      let acc = print_keyword("}", loc, acc, err)
      #(acc, info)
    }
  }
}

fn print_match(source, loc, br, br_inner, acc, info, analysis) {
  let err = is_error(loc.path, analysis)
  let #(exp, _meta) = source
  case exp {
    ir.NoCases -> {
      let acc = print_keyword(br, loc, acc, err)
      let info = dict.insert(info, path_to_string(loc.path), list.length(acc))

      let acc = print_keyword("}", loc, acc, err)
      #(acc, info)
    }
    ir.Apply(#(ir.Apply(#(ir.Case(label), _), item), _), tail) -> {
      let acc = print_keyword(br_inner, loc, acc, err)
      let info = dict.insert(info, path_to_string(loc.path), list.length(acc))
      let #(acc, info) =
        print_with_offset(label, loc, Label, err, acc, info, analysis)
      let acc = print_keyword(" ", loc, acc, err)
      let #(acc, info) =
        print_block(
          item,
          location.child(location.child(loc, 0), 1),
          br_inner,
          acc,
          info,
          analysis,
        )
      print_match(
        tail,
        location.child(loc, 1),
        br,
        br_inner,
        acc,
        info,
        analysis,
      )
    }
    _ -> {
      let acc = print_keyword(br_inner, loc, acc, err)
      let info = dict.insert(info, path_to_string(loc.path), list.length(acc))
      let #(acc, info) = print_block(source, loc, br_inner, acc, info, analysis)
      let acc = print_keyword(br, loc, acc, err)
      let acc = print_keyword("}", loc, acc, err)
      #(acc, info)
    }
  }
}

pub fn print_keyword(keyword, loc, acc, err) {
  let Location(path: path, ..) = loc
  // list.fold(
  //   string.to_graphemes(keyword),
  stringx.fold_graphemes(keyword, acc, fn(acc, ch) {
    [#(ch, path, -1, Keyword, err), ..acc]
  })
}

pub fn print_with_offset(content, loc, style, err, acc, info, _analysis) {
  let Location(path: path, ..) = loc
  let info = dict.insert(info, path_to_string(loc.path), list.length(acc))
  let #(content, style) = case content {
    "" -> #("_", Missing)
    _ -> #(content, style)
  }
  let acc =
    stringx.index_fold_graphemes(
      // list.index_fold(
      //   string.to_graphemes(content),
      content,
      acc,
      fn(acc, ch, i) { [#(ch, path, i, style, err), ..acc] },
    )
  #(acc, info)
}

pub fn path_to_string(path) {
  list.map(path, int.to_string)
  |> string.join("j")
}
