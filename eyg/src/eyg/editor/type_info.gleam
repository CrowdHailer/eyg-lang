import gleam/io
import gleam/int
import gleam/list
import gleam/option.{None, Option, Some}
import gleam/string
import eyg/ast/expression as e
import eyg/typer/monotype as t
// TODO remove typer because we should probably just resolve before printing.
import eyg/typer.{Typer}

fn field_to_string(field, ) {
  let #(label, type_) = field
  string.concat([label, ": ", to_string(type_, )])
}

fn variant_to_string(variant, ) {
  let #(label, type_) = variant
  string.concat([label, " ", to_string(type_, )])
}

pub fn to_string(monotype, ) {
  case monotype {
    t.Native(name, parameters) -> string.concat([
        name,
        "(",
        string.concat(list.intersperse(
          list.map(parameters, to_string(_, )),
          ", ",
        )),
        ")",
      ])
    t.Binary -> "Binary"
    t.Tuple(elements) ->
      string.concat([
        "(",
        string.concat(list.intersperse(
          list.map(elements, to_string(_, )),
          ", ",
        )),
        ")",
      ])
    t.Record(fields, extra) -> {
      let extra = case extra {
        Some(i) -> [string.concat(["..", int.to_string(i)])]
        None -> []
      }
      string.concat([
        "{",
        string.concat(list.intersperse(
          list.map(fields, field_to_string(_, ))
          |> list.append(extra),
          ", ",
        )),
        "}",
      ])
    }
    t.Union(variants, extra) -> {
      let extra = case extra {
        Some(i) -> [string.concat(["..", int.to_string(i)])]
        None -> []
      }
      string.concat([
        "[",
        string.concat(list.intersperse(
          list.map(variants, variant_to_string(_, ))
          |> list.append(extra),
          " | ",
        )),
        "]",
      ])
    }
    // TODO render effects here
    t.Function(from, to, _) ->
      string.concat([
        to_string(from, ),
        " -> ",
        to_string(to, ),
      ])
    t.Unbound(i) -> int.to_string(i)
    t.Recursive(i, inner) -> {
      let inner = to_string(inner, )
      string.concat(["μ", int.to_string(i), ".", inner])
    }
  }
}

pub fn resolve_reason(reason, typer: Typer) {
  case reason {
    typer.IncorrectArity(expected, given) -> reason
    typer.UnknownVariable(label) -> reason
    typer.UnmatchedTypes(expected, given) ->
      typer.UnmatchedTypes(
        t.resolve(expected, typer.substitutions),
        t.resolve(given, typer.substitutions),
      )

    typer.MissingFields(expected) ->
      typer.MissingFields(list.map(
        expected,
        fn(field) {
          let #(name, type_) = field
          #(name, t.resolve(type_, typer.substitutions))
        },
      ))
    typer.UnexpectedFields(expected) ->
      typer.UnexpectedFields(list.map(
        expected,
        fn(field) {
          let #(name, type_) = field
          #(name, t.resolve(type_, typer.substitutions))
        },
      ))
    typer.ProviderFailed(g, expected) ->
      typer.ProviderFailed(g, t.resolve(expected, typer.substitutions))

    typer.ProviderFailed(g, expected) ->
      typer.ProviderFailed(g, t.resolve(expected, typer.substitutions))

    typer.GeneratedInvalid(reasons) ->
      typer.GeneratedInvalid(list.map(
        reasons,
        fn(sub) {
          let #(path, reason) = sub
          let reason = resolve_reason(reason, typer)
          #(path, reason)
        },
      ))
    typer.Warning(message) -> reason
  }
}

pub fn reason_to_string(reason, ) {
  case reason {
    typer.IncorrectArity(expected, given) ->
      string.concat([
        "Incorrect Arity expected ",
        int.to_string(expected),
        " given ",
        int.to_string(given),
      ])
    typer.UnknownVariable(label) ->
      string.concat(["Unknown variable: \"", label, "\""])
    typer.UnmatchedTypes(expected, given) ->
      string.concat([
        "Unmatched types expected ",
        to_string(expected, ),
        " given ",
        to_string(given, ),
      ])
    typer.MissingFields(expected) ->
      [
        "Missing fields: ",
        ..list.map(
          expected,
          fn(x) {
            let #(name, type_) = x
            string.concat([name, ": ", to_string(type_, )])
          },
        )
        |> list.intersperse(", ")
      ]
      |> string.concat

    typer.UnexpectedFields(expected) ->
      [
        "Unexpected fields: ",
        ..list.map(
          expected,
          fn(x) {
            let #(name, type_) = x
            string.concat([name, ": ", to_string(type_, )])
          },
        )
        |> list.intersperse(", ")
      ]
      |> string.concat
    typer.ProviderFailed(g, expected) ->
      string.concat([
        "Provider '",
        e.generator_to_string(g),
        "' unable to generate code for type: ",
        to_string(expected, ),
      ])
    typer.Warning(message) -> message
    typer.GeneratedInvalid(reasons) -> {
      io.debug(reasons)
      "Generated invalid code"
    }
  }
}
