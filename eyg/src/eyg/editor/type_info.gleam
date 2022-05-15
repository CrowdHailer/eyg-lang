import gleam/io
import gleam/int
import gleam/list
import gleam/option.{None, Option, Some}
import gleam/string
import eyg/ast/expression as e
import eyg/typer/monotype as t
// TODO remove typer because we should probably just resolve before printing.
import eyg/typer.{Typer}

fn field_to_string(field, native_to_string) {
  let #(label, type_) = field
  string.concat([label, ": ", to_string(type_, native_to_string)])
}

fn variant_to_string(variant, native_to_string) {
  let #(label, type_) = variant
  string.concat([label, " ", to_string(type_, native_to_string)])
}

pub fn to_string(monotype, native_to_string) {
  case monotype {
    t.Native(native) -> native_to_string(native)
    t.Binary -> "Binary"
    t.Tuple(elements) ->
      string.concat([
        "(",
        string.concat(list.intersperse(
          list.map(elements, to_string(_, native_to_string)),
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
          list.map(fields, field_to_string(_, native_to_string))
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
          list.map(variants, variant_to_string(_, native_to_string))
          |> list.append(extra),
          " | ",
        )),
        "]",
      ])
    }
    t.Function(from, to) ->
      string.concat([
        to_string(from, native_to_string),
        " -> ",
        to_string(to, native_to_string),
      ])
    t.Unbound(i) -> int.to_string(i)
    t.Recursive(i, inner) -> {
      let inner = to_string(inner, native_to_string)
      string.concat(["μ", int.to_string(i), ".", inner])
    }
  }
}

pub fn resolve_reason(reason, typer: Typer(n)) {
  case reason {
    typer.IncorrectArity(expected, given) -> reason
    typer.UnknownVariable(label) -> reason
    typer.UnmatchedTypes(expected, given) ->
      typer.UnmatchedTypes(
        t.resolve(expected, typer.substitutions),
        t.resolve(given, typer.substitutions),
      )

    typer.MissingFields(expected) -> todo
    // TODO resolve field function
    // typer.MissingFields(list.map(expected, ))
    //   [
    //     "Missing fields: ",
    //     ..list.map(
    //       expected,
    //       fn(x) {
    //         let #(name, type_) = x
    //         string.concat([
    //           name,
    //           ": ",
    //           to_string(
    //             t.resolve(type_, typer.substitutions),
    //             native_to_string,
    //           ),
    //         ])
    //       },
    //     )
    //     |> list.intersperse(", ")
    //   ]
    //   |> string.concat
    typer.UnexpectedFields(expected) -> todo
    //   [
    //     "Unexpected fields: ",
    //     ..list.map(
    //       expected,
    //       fn(x) {
    //         let #(name, type_) = x
    //         string.concat([
    //           name,
    //           ": ",
    //           to_string(
    //             t.resolve(type_, typer.substitutions),
    //             native_to_string,
    //           ),
    //         ])
    //       },
    //     )
    //     |> list.intersperse(", ")
    //   ]
    //   |> string.concat
    typer.UnableToProvide(expected, g) ->
      typer.UnableToProvide(t.resolve(expected, typer.substitutions), g)

    typer.ProviderFailed(g, expected) ->
      typer.ProviderFailed(g, t.resolve(expected, typer.substitutions))

    typer.Warning(message) -> reason
  }
}

// TODO uses need to resolve first
pub fn reason_to_string(reason, native_to_string) {
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
        to_string(expected, native_to_string),
        " given ",
        to_string(given, native_to_string),
      ])
    typer.MissingFields(expected) ->
      [
        "Missing fields: ",
        ..list.map(
          expected,
          fn(x) {
            let #(name, type_) = x
            string.concat([name, ": ", to_string(type_, native_to_string)])
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
            string.concat([name, ": ", to_string(type_, native_to_string)])
          },
        )
        |> list.intersperse(", ")
      ]
      |> string.concat
    typer.UnableToProvide(expected, g) ->
      string.concat([
        "Unable to generate for expected type ",
        to_string(expected, native_to_string),
        " with generator ",
        e.generator_to_string(g),
      ])
    typer.ProviderFailed(g, expected) ->
      string.concat([
        "Provider '",
        e.generator_to_string(g),
        "' unable to generate code for type: ",
        to_string(expected, native_to_string),
      ])
    typer.Warning(message) -> message
  }
}