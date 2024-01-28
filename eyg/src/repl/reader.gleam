import gleam/io
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import glexer
import glexer/token as t
import glance as g

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

pub fn parse(lines) {
  let ts = tokens(lines)
  case ts {
    // [#(t.At, _), ..tokens] -> {
    //   use #(attribute, tokens) <- result.try(attribute(tokens))
    //   slurp(module, [attribute, ..attributes], tokens)
    // }
    [#(t.Import, _), ..tokens] -> {
      let result = g.do_import_statement([], tokens)
      use #(g.Definition([], definition), tokens) <- result.try(result)
      let g.Import(module, alias, _types, values) = definition
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
      Ok(Import(module, binding, unqualified))
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
      let result = g.type_definition(module, [], g.Private, False, tokens)
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
      Ok(CustomType(variants))
    }
    [#(t.Pub, _), #(t.Const, _), ..tokens] -> {
      let result = g.do_const_definition(g.Public, tokens)
      use #(c, tokens) <- result.try(result)
      Ok(Constant(c.name, c.value))
    }
    [#(t.Const, _), ..tokens] -> {
      let result = g.do_const_definition(g.Private, tokens)
      use #(c, tokens) <- result.try(result)
      Ok(Constant(c.name, c.value))
    }

    [#(t.Pub, start), #(t.Fn, _), #(t.Name(name), _), ..tokens] -> {
      let glexer.Position(start) = start
      let result = g.do_function_definition(g.Public, name, start, tokens)
      use #(f, tokens) <- result.try(result)
      Ok(Function(f.name, f.parameters, f.body))
    }
    [#(t.Fn, start), #(t.Name(name), _), ..tokens] -> {
      let glexer.Position(start) = start
      let result = g.do_function_definition(g.Private, name, start, tokens)
      use #(f, tokens) <- result.try(result)
      Ok(Function(f.name, f.parameters, f.body))
    }
    _ -> {
      use #(statements, _, tokens) <- result.try(statements([], ts))
      Ok(Statements(statements))
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
        [] -> Ok(#(list.reverse(acc), Nil, Nil))
        _ -> statements(acc, rest)
      }
    }
    Error(reason) -> Error(reason)
  }
}
