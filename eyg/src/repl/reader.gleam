import gleam/io
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import glexer
import glexer/token as t
import glance as g
import repl/reason as r

pub type Term {
  Import(module: String, binding: String, unqualified: List(#(String, String)))
  CustomType(List(#(String, List(Option(String)))))
  Constant(name: String, expression: g.Expression)
  Function(
    name: String,
    parameters: List(g.FunctionParameter),
    body: List(g.Statement),
  )
  Statements(List(g.Statement))
}

pub fn module(src) {
  g.module(src)
}

pub fn tokens(src) {
  glexer.new(src)
  |> glexer.lex
  |> list.filter(fn(pair) { !g.is_whitespace(pair.0) })
}

pub type Reason {
  Unsupported(String)
  ParseFail(g.Error)
}

pub fn parse(lines) {
  let ts = tokens(lines)
  case ts {
    [#(t.At, _), ..] -> {
      Error(Unsupported("attributes"))
    }
    [#(t.Import, _), ..tokens] -> {
      let result = result.map_error(g.do_import_statement(tokens), ParseFail)
      use #(import_, tokens) <- result.try(result)
      let g.Import(module, alias, _types, values) = import_
      let binding = case alias {
        Some(label) -> label
        None -> {
          let assert [label, ..] = list.reverse(string.split(module, "/"))
          label
        }
      }
      let unqualified =
        list.map(values, fn(v) {
          let g.UnqualifiedImport(field, label) = v
          let label = option.unwrap(label, field)
          #(field, label)
        })
      let import_ = Import(module, binding, unqualified)
      Ok(#(import_, tokens))
    }
    // Not supported because how do we handle the type parameters and aliases
    // [#(t.Pub, _), #(t.Type, _), ..tokens] -> {
    //   let result = type_definition(module, attributes, Public, False, tokens)
    //   use #(module, tokens) <- result.try(result)
    //   slurp(module, [], tokens)
    // }
    // [#(t.Pub, _), #(t.Opaque, _), #(t.Type, _), ..tokens] -> {
    //   let result = type_definition(module, attributes, Public, True, tokens)
    //   use #(module, tokens) <- result.try(result)
    //   slurp(module, [], tokens)
    // }
    [#(t.Type, _), ..tokens] -> {
      let module = g.Module([], [], [], [], [], [], [])
      let result =
        result.map_error(
          g.type_definition(module, [], g.Private, False, tokens),
          ParseFail,
        )
      use #(module, tokens) <- result.try(result)
      let variants =
        list.flat_map(module.custom_types, fn(definition) {
          let g.Definition(_, g.CustomType(variants: variants, ..)) = definition
          list.map(variants, fn(v) {
            let g.Variant(name, fields) = v
            let labels = list.map(fields, fn(f: g.Field(_)) { f.label })
            #(name, labels)
          })
        })
      Ok(#(CustomType(variants), tokens))
    }
    [#(t.Pub, _), #(t.Const, _), ..tokens] -> {
      let result =
        result.map_error(g.do_const_definition(g.Public, tokens), ParseFail)
      use #(c, tokens) <- result.try(result)
      Ok(#(Constant(c.name, c.value), tokens))
    }
    [#(t.Const, _), ..tokens] -> {
      let result =
        result.map_error(g.do_const_definition(g.Private, tokens), ParseFail)
      use #(c, tokens) <- result.try(result)
      Ok(#(Constant(c.name, c.value), tokens))
    }

    [#(t.Pub, start), #(t.Fn, _), #(t.Name(name), _), ..tokens] -> {
      let glexer.Position(start) = start
      let result =
        result.map_error(
          g.do_function_definition(g.Public, name, start, tokens),
          ParseFail,
        )
      use #(f, tokens) <- result.try(result)
      let function = Function(f.name, f.parameters, f.body)
      Ok(#(function, tokens))
    }
    [#(t.Fn, start), #(t.Name(name), _), ..tokens] -> {
      let glexer.Position(start) = start
      let result =
        result.map_error(
          g.do_function_definition(g.Private, name, start, tokens),
          ParseFail,
        )
      use #(f, tokens) <- result.try(result)
      let function = Function(f.name, f.parameters, f.body)
      Ok(#(function, tokens))
    }
    _ -> {
      use #(statements, _, tokens) <- result.try(statements([], ts))
      Ok(#(Statements(statements), tokens))
    }
  }
}

// The statements fn in glance looks for closing right brace
// glance parses statements assuming a block
pub fn statements(acc, tokens) {
  case g.statement(tokens) {
    Ok(#(statement, rest)) -> {
      let acc = [statement, ..acc]
      case rest {
        [] -> Ok(#(list.reverse(acc), Nil, []))
        _ -> statements(acc, rest)
      }
    }
    Error(reason) -> Error(ParseFail(reason))
  }
}
