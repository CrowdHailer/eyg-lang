import gleam/option.{Some}
import gleam/list
import gleam/io
import eyg/typer/monotype.{
  Binary, Function, Monotype, Nominal, Row, Tuple, Unbound,
}

pub type Polytype {
  Polytype(forall: List(Int), monotype: Monotype)
}

pub fn instantiate(polytype, typer) {
  let Polytype(forall, monotype) = polytype
  do_instantiate(forall, monotype, typer)
}

fn do_instantiate(forall, monotype, typer) {
  case forall {
    [] -> monotype
    [variable, ..rest] -> {
      let dummy = 1111
      replace_variable(monotype, variable, dummy)
    }
  }
}

fn replace_variable(monotype, x, y) {
  case monotype {
    Binary -> Binary
    Tuple(elements) -> Tuple(list.map(elements, replace_variable(_, x, y)))
    Row(fields, rest) -> {
      let fields =
        list.map(
          fields,
          fn(field) {
            let #(name, value) = field
            #(name, replace_variable(value, x, y))
          },
        )
      let rest = case rest {
        Some(i) if i == x -> Some(y)
        _ -> rest
      }
      Row(fields, rest)
    }
    Nominal(name, elements) ->
      Nominal(name, list.map(elements, replace_variable(_, x, y)))
    Function(from, to) ->
      Function(replace_variable(from, x, y), replace_variable(to, x, y))
    Unbound(i) ->
      case i == x {
        True -> Unbound(y)
        False -> Unbound(i)
      }
  }
}

pub fn generalise(monotype) {
  // TODO generalise fns
  Polytype([], monotype)
}
