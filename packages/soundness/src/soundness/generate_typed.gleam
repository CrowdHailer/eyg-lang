//// Generates programs from the type rules.
////
//// Every program this produces is well typed according to the rules as they
//// are written down: the types in the builtin table and the shapes the
//// inference gives to lambdas, records, unions and handlers. The analysis
//// should therefore accept all of them, and if a rule says something eval
//// does not honour then one of these programs will fail to run.
////
//// Generating from the rules is what makes this worth doing. Randomly built
//// programs are rejected by the analysis about 199 times in 200, and the
//// interesting programs, the deep ones, are never reached at all.
////
//// Generation is indexed by the effects allowed at each point, the ambient
//// row. A function type carries its own row, so a function that performs an
//// effect can be built anywhere, passed around, and only called where that
//// effect is handled. That is the shape of program where the interesting
//// questions about effects live.

import eyg/analysis/inference/levels_j/contextual as j
import eyg/analysis/type_/isomorphic as t
import eyg/ir/tree as ir
import gleam/int
import gleam/list
import soundness/random

const fields = ["a", "b", "c"]

const tags = ["Ok", "Error", "Some"]

/// The effects a generated program can use, with the type carried up to the
/// handler and the type sent back to the point that performed it.
pub fn effects() {
  [#("Log", #(t.String, t.unit)), #("Ask", #(t.unit, t.Integer))]
}

pub type Config {
  Config(
    /// Include recursion, which can generate programs that do not terminate.
    fix: Bool,
    /// Include effects and the handlers that discharge them.
    effects: Bool,
    /// Include records that carry the same label twice. Such a type is
    /// rejected by the analysis now, this is how that was found.
    shadowed_rows: Bool,
    /// Bind polymorphic functions and use them at more than one type.
    polymorphism: Bool,
  )
}

pub fn everything() {
  Config(fix: True, effects: True, shadowed_rows: False, polymorphism: True)
}

pub fn program(seed, config, size) {
  let #(type_, seed) = sample_type(seed, config, 2)
  let #(node, seed) = term(seed, config, Scope([], []), type_, [], size)
  #(node, type_, seed)
}

/// Variables of a known type, and variables bound to a polymorphic function.
///
/// A polymorphic binding is the only way to reach the generalisation the
/// analysis does at a let, so the templates are held separately and used at
/// whatever type is being generated at the time.
pub type Scope(var) {
  Scope(mono: List(#(String, t.Type(var))), poly: List(#(String, Template)))
}

pub type Template {
  /// `(x) -> { x }` used as `p(value)`
  Identity
  /// `(x) -> { (_) -> { x } }` used as `p(value)(anything)`
  Constant
  /// `(x) -> { [x] }` used as `p(value)` for a list of anything
  Singleton
  /// `(r) -> { {a: 1, ..r} }`, a row polymorphic function, used to build any
  /// record that has an Integer `a` on top of another record
  Extender
  /// `(r) -> { r.a }`, the other side of row polymorphism, used to produce a
  /// value of any type out of a record that has a field of that type
  Selector
}

fn template(chosen) {
  case chosen {
    Identity -> ir.lambda("x", ir.variable("x"))
    Constant -> ir.lambda("x", ir.lambda("_", ir.variable("x")))
    Singleton ->
      ir.lambda("x", ir.apply(ir.apply(ir.cons(), ir.variable("x")), ir.tail()))
    Extender ->
      ir.lambda(
        "r",
        ir.apply(ir.apply(ir.extend("a"), ir.integer(1)), ir.variable("r")),
      )
    Selector -> ir.lambda("r", ir.apply(ir.select("a"), ir.variable("r")))
  }
}

// --- effect rows

/// Rows are built in a fixed order so that two rows with the same labels are
/// the same type.
pub fn row(labels) {
  list.fold_right(effects(), t.Empty, fn(tail, effect) {
    let #(label, #(lift, reply)) = effect
    case list.contains(labels, label) {
      True -> t.EffectExtend(label, #(lift, reply), tail)
      False -> tail
    }
  })
}

fn sample_labels(seed, available) {
  list.fold(available, #([], seed), fn(acc, label) {
    let #(labels, seed) = acc
    let #(keep, seed) = random.int(seed, 3)
    case keep {
      0 -> #([label, ..labels], seed)
      _ -> #(labels, seed)
    }
  })
}

fn carried(label) {
  let assert Ok(pair) = list.key_find(effects(), label)
  pair
}

// --- types

pub fn sample_type(seed, config: Config, depth) {
  case depth <= 0 {
    True -> {
      let #(choice, seed) = random.int(seed, 4)
      case choice {
        0 -> #(t.Integer, seed)
        1 -> #(t.String, seed)
        2 -> #(t.Binary, seed)
        _ -> #(t.unit, seed)
      }
    }
    False -> {
      let #(choice, seed) = random.int(seed, 9)
      case choice {
        0 -> #(t.Integer, seed)
        1 -> #(t.String, seed)
        2 -> #(t.Binary, seed)
        3 -> {
          let #(inner, seed) = sample_type(seed, config, depth - 1)
          #(t.List(inner), seed)
        }
        4 -> {
          let #(inner, seed) = sample_type(seed, config, depth - 1)
          let #(label, seed) = random.pick(seed, fields)
          #(t.record([#(label, inner)]), seed)
        }
        5 -> record_type(seed, config, depth)
        6 -> {
          let #(inner, seed) = sample_type(seed, config, depth - 1)
          let #(label, seed) = random.pick(seed, tags)
          #(t.union([#(label, inner)]), seed)
        }
        _ -> {
          let #(argument, seed) = sample_type(seed, config, depth - 1)
          let #(return, seed) = sample_type(seed, config, depth - 1)
          let #(labels, seed) = case config.effects {
            True -> sample_labels(seed, list.map(effects(), fn(e) { e.0 }))
            False -> #([], seed)
          }
          #(t.Fun(argument, row(labels), return), seed)
        }
      }
    }
  }
}

/// A record with two fields, sometimes both with the same label. A row that
/// carries a label twice is a type the rules allow to be built.
fn record_type(seed, config: Config, depth) {
  let #(first, seed) = sample_type(seed, config, depth - 1)
  let #(second, seed) = sample_type(seed, config, depth - 1)
  let #(one, seed) = random.pick(seed, fields)
  let #(other, seed) = case config.shadowed_rows {
    True -> {
      let #(same, seed) = random.int(seed, 2)
      case same {
        0 -> #(one, seed)
        _ -> random.pick(seed, fields)
      }
    }
    False -> random.pick(seed, fields)
  }
  case one == other && !config.shadowed_rows {
    True -> #(t.record([#(one, first)]), seed)
    False -> #(t.record([#(one, first), #(other, second)]), seed)
  }
}

/// A value of any type, used when there is no budget left to build something
/// more interesting.
pub fn literal(seed, type_) {
  case type_ {
    t.Integer -> {
      let #(value, seed) = random.int(seed, 9)
      #(ir.integer(value), seed)
    }
    t.String -> #(ir.string("s"), seed)
    t.Binary -> #(ir.binary(<<0, 1>>), seed)
    t.List(_) -> #(ir.tail(), seed)
    t.Record(rows) -> record_literal(seed, rows)
    t.Union(t.RowExtend(label, inner, _)) -> {
      let #(value, seed) = literal(seed, inner)
      #(ir.apply(ir.tag(label), value), seed)
    }
    t.Fun(_, _, return) -> {
      let #(value, seed) = literal(seed, return)
      #(ir.lambda("_", value), seed)
    }
    // Never, an empty union and open rows are not generated as types.
    _ -> #(ir.empty(), seed)
  }
}

fn record_literal(seed, rows) {
  case rows {
    t.RowExtend(label, inner, tail) -> {
      let #(rest, seed) = record_literal(seed, tail)
      let #(value, seed) = literal(seed, inner)
      #(ir.apply(ir.apply(ir.extend(label), value), rest), seed)
    }
    _ -> #(ir.empty(), seed)
  }
}

// --- terms

/// Generate a term of the given type, using only the effects in ambient.
pub fn term(seed, config: Config, scope: Scope(_), type_, ambient, size) {
  case size <= 1 {
    True -> variable(seed, scope, type_)
    False -> {
      let #(form, seed) =
        random.weighted(
          seed,
          forms(config, scope, type_, in_scope(scope, type_)),
        )
      build(seed, config, scope, type_, ambient, size, form)
    }
  }
}

fn in_scope(scope: Scope(_), type_) {
  list.filter(scope.mono, fn(entry) {
    let #(_label, bound) = entry
    bound == type_
  })
}

fn bind(scope: Scope(_), label, type_) {
  Scope(..scope, mono: [#(label, type_), ..scope.mono])
}

fn variable(seed, scope, type_) {
  case in_scope(scope, type_) {
    [] -> literal(seed, type_)
    candidates -> {
      let #(#(label, _type), seed) = random.pick(seed, candidates)
      #(ir.variable(label), seed)
    }
  }
}

type Form {
  Literal
  Variable
  Binding
  Beta
  Function
  Builtin
  Select
  Match
  Cons
  Recurse
  Handled
  Performed
  PolyBinding
  PolyUse
}

fn forms(config: Config, scope: Scope(_), type_, in_scope) {
  let structural = case type_ {
    t.Fun(_, _, _) -> [#(8, Function), #(2, Literal)]
    t.List(_) -> [#(6, Cons), #(2, Literal)]
    _ -> [#(3, Literal)]
  }
  let recursion = case config.fix, type_ {
    True, t.Fun(_, _, _) -> [#(4, Recurse)]
    _, _ -> []
  }
  let handlers = case config.effects {
    True -> [#(6, Handled), #(4, Performed)]
    False -> []
  }
  let variables = case in_scope {
    [] -> []
    _ -> [#(6, Variable)]
  }
  let polymorphism = case config.polymorphism, scope.poly {
    True, [] -> [#(5, PolyBinding)]
    True, _ -> [#(3, PolyBinding), #(8, PolyUse)]
    False, _ -> []
  }
  list.flatten([
    structural,
    recursion,
    handlers,
    variables,
    polymorphism,
    [#(6, Binding), #(5, Beta), #(8, Builtin), #(4, Select), #(5, Match)],
  ])
}

fn build(seed, config: Config, scope, type_, ambient, size, form) {
  case form {
    Literal -> literal(seed, type_)
    Variable -> variable(seed, scope, type_)
    Binding -> {
      let #(bound, seed) = sample_type(seed, config, 1)
      let #(definition, seed) =
        term(seed, config, scope, bound, ambient, size / 2)
      let label = name(scope)
      let #(body, seed) =
        term(seed, config, bind(scope, label, bound), type_, ambient, size / 2)
      #(ir.let_(label, definition, body), seed)
    }
    Beta -> {
      // The function is applied here so it can only perform effects that are
      // handled here.
      let #(bound, seed) = sample_type(seed, config, 1)
      let #(labels, seed) = sample_labels(seed, ambient)
      let #(argument, seed) =
        term(seed, config, scope, bound, ambient, size / 3)
      let #(func, seed) =
        term(
          seed,
          config,
          scope,
          t.Fun(bound, row(labels), type_),
          ambient,
          size - { size / 3 },
        )
      #(ir.apply(func, argument), seed)
    }
    Function -> {
      let assert t.Fun(argument, effect, return) = type_
      let label = name(scope)
      let #(body, seed) =
        term(
          seed,
          config,
          bind(scope, label, argument),
          return,
          labels_of(effect),
          size - 1,
        )
      #(ir.lambda(label, body), seed)
    }
    Builtin -> builtin(seed, config, scope, type_, ambient, size)
    Select -> {
      let #(label, seed) = random.pick(seed, fields)
      let #(record, seed) =
        term(
          seed,
          config,
          scope,
          t.record([#(label, type_)]),
          ambient,
          size - 1,
        )
      #(ir.apply(ir.select(label), record), seed)
    }
    Match -> {
      let #(label, seed) = random.pick(seed, tags)
      let #(carried, seed) = sample_type(seed, config, 1)
      let branch_type = t.Fun(carried, row(ambient), type_)
      let otherwise_type = t.Fun(t.Union(t.Empty), row(ambient), type_)
      let #(branch, seed) =
        term(seed, config, scope, branch_type, ambient, { size - 1 } / 3)
      let #(otherwise, seed) =
        term(seed, config, scope, otherwise_type, ambient, { size - 1 } / 3)
      let #(value, seed) =
        term(
          seed,
          config,
          scope,
          t.union([#(label, carried)]),
          ambient,
          { size - 1 } / 3,
        )
      #(
        ir.apply(ir.apply(ir.apply(ir.case_(label), branch), otherwise), value),
        seed,
      )
    }
    Cons -> {
      let assert t.List(element) = type_
      let #(head, seed) = term(seed, config, scope, element, ambient, size / 2)
      let #(tail, seed) = term(seed, config, scope, type_, ambient, size / 2)
      #(ir.apply(ir.apply(ir.cons(), head), tail), seed)
    }
    Recurse -> {
      // fix is typed `((self) -> self) -> self`, the constructor is pure and
      // returns a function, so it is generated as a lambda with self bound.
      let label = name(scope)
      let #(body, seed) =
        term(seed, config, bind(scope, label, type_), type_, [], size - 2)
      #(ir.apply(ir.builtin("fix"), ir.lambda(label, body)), seed)
    }
    PolyBinding -> {
      // A let bound function with no annotation, the analysis generalises it
      // and every use below instantiates it again.
      let #(chosen, seed) =
        random.pick(seed, [Identity, Constant, Singleton, Extender, Selector])
      let label = name(scope)
      let scope = Scope(..scope, poly: [#(label, chosen), ..scope.poly])
      let #(body, seed) = term(seed, config, scope, type_, ambient, size - 2)
      #(ir.let_(label, template(chosen), body), seed)
    }
    PolyUse -> {
      case use_polymorphic(seed, config, scope, type_, ambient, size) {
        Ok(generated) -> generated
        Error(Nil) -> literal(seed, type_)
      }
    }
    Handled -> handled(seed, config, scope, type_, ambient, size)
    Performed -> {
      case ambient {
        [] -> literal(seed, type_)
        _ -> {
          let #(label, seed) = random.pick(seed, ambient)
          let #(lift, reply) = carried(label)
          let #(lifted, seed) =
            term(seed, config, scope, lift, ambient, { size - 1 } / 2)
          let performed = ir.apply(ir.perform(label), lifted)
          // The reply is fed to a function so that the type of the whole
          // expression is the type that was asked for.
          let name = name(scope)
          let #(body, seed) =
            term(
              seed,
              config,
              bind(scope, name, reply),
              type_,
              ambient,
              { size - 1 } / 2,
            )
          #(ir.apply(ir.lambda(name, body), performed), seed)
        }
      }
    }
  }
}

/// `handle Label(handler, exec)`
///
/// The handler is `(lift) -> (resume) -> return` and exec is a thunk that may
/// perform the effect. Inside exec the effect is part of the ambient row, in
/// the handler it is not, the handler runs outside itself.
fn handled(seed, config, scope, type_, ambient, size) {
  let #(label, seed) = random.pick(seed, list.map(effects(), fn(e) { e.0 }))
  let #(lift, reply) = carried(label)

  let lift_label = name(scope)
  let handler_scope = bind(scope, lift_label, lift)
  let resume_label = name(handler_scope)
  let resume_type = t.Fun(reply, row(ambient), type_)
  let handler_scope = bind(handler_scope, resume_label, resume_type)

  let #(body, seed) =
    term(seed, config, handler_scope, type_, ambient, { size - 2 } / 2)
  let handler = ir.lambda(lift_label, ir.lambda(resume_label, body))

  let inner = case list.contains(ambient, label) {
    True -> ambient
    False -> [label, ..ambient]
  }
  let #(execed, seed) =
    term(seed, config, scope, type_, inner, { size - 2 } / 2)
  let exec = ir.lambda("_", execed)
  #(ir.apply(ir.apply(ir.handle(label), handler), exec), seed)
}

/// Use a polymorphic binding at the type being generated.
///
/// Identity and Constant can produce any type, Singleton only a list, so the
/// candidates are filtered by what is being asked for.
fn use_polymorphic(seed, config, scope: Scope(_), type_, ambient, size) {
  let candidates =
    list.filter(scope.poly, fn(entry) {
      let #(_label, chosen) = entry
      case chosen, type_ {
        Singleton, t.List(_) -> True
        Singleton, _ -> False
        // The extender builds a record with an Integer `a` on the front of
        // whatever it is given, so it can only produce such a record.
        Extender, t.Record(t.RowExtend("a", t.Integer, _)) -> True
        Extender, _ -> False
        _, _ -> True
      }
    })
  case candidates {
    [] -> Error(Nil)
    _ -> {
      let #(#(label, chosen), seed) = random.pick(seed, candidates)
      case chosen {
        Identity -> {
          let #(argument, seed) =
            term(seed, config, scope, type_, ambient, size - 1)
          Ok(#(ir.apply(ir.variable(label), argument), seed))
        }
        Constant -> {
          let #(argument, seed) =
            term(seed, config, scope, type_, ambient, { size - 1 } / 2)
          let #(dropped, seed) = sample_type(seed, config, 1)
          let #(other, seed) =
            term(seed, config, scope, dropped, ambient, { size - 1 } / 2)
          Ok(#(ir.apply(ir.apply(ir.variable(label), argument), other), seed))
        }
        Singleton -> {
          let assert t.List(element) = type_
          let #(argument, seed) =
            term(seed, config, scope, element, ambient, size - 1)
          Ok(#(ir.apply(ir.variable(label), argument), seed))
        }
        Extender -> {
          let assert t.Record(t.RowExtend("a", t.Integer, rest)) = type_
          let #(argument, seed) =
            term(seed, config, scope, t.Record(rest), ambient, size - 1)
          Ok(#(ir.apply(ir.variable(label), argument), seed))
        }
        Selector -> {
          // The record the field is taken from is built here, with a second
          // field as often as not, so the row the function is used at is a
          // different one each time.
          let #(extra, seed) = random.int(seed, 2)
          let #(record, seed) = case extra {
            0 -> #(t.record([#("a", type_)]), seed)
            _ -> {
              let #(other, seed) = sample_type(seed, config, 1)
              let #(label, seed) = random.pick(seed, ["b", "c"])
              #(t.record([#("a", type_), #(label, other)]), seed)
            }
          }
          let #(argument, seed) =
            term(seed, config, scope, record, ambient, size - 1)
          Ok(#(ir.apply(ir.variable(label), argument), seed))
        }
      }
    }
  }
}

fn labels_of(effect) {
  case effect {
    t.EffectExtend(label, _, tail) -> [label, ..labels_of(tail)]
    _ -> []
  }
}

fn name(scope: Scope(_)) {
  "v" <> int.to_string(list.length(scope.mono) + list.length(scope.poly))
}

// --- builtins

/// Pick a builtin whose return type can be made to match the requested type,
/// then generate its arguments.
fn builtin(seed, config, scope, type_, ambient, size) {
  let #(candidates, seed) = shuffle_once(seed, matching(type_))
  case candidates {
    [] -> literal(seed, type_)
    [#(name, arguments), ..] -> {
      let budget = size / { list.length(arguments) + 1 }
      list.fold(arguments, #(ir.builtin(name), seed), fn(acc, argument) {
        let #(func, seed) = acc
        let #(node, seed) = term(seed, config, scope, argument, ambient, budget)
        #(ir.apply(func, node), seed)
      })
    }
  }
}

/// Every builtin that returns the requested type, with the types of the
/// arguments it needs. Quantified variables in the builtin type are matched
/// against the requested type, any that are still free are filled in with the
/// requested type itself, which keeps the generated program simple.
fn matching(wanted) {
  list.filter_map(j.builtins(), fn(entry) {
    let #(name, scheme) = entry
    case peel(scheme, [], wanted) {
      Ok(arguments) ->
        case list.all(arguments, inhabited) {
          True -> Ok(#(name, arguments))
          False -> Error(Nil)
        }
      Error(Nil) -> Error(Nil)
    }
  })
}

/// Is there any value of this type?
///
/// `!never` takes a `Never` and a union with no tags has no values either.
/// Neither can be generated as an argument, they only appear as the return
/// type of an expression that does not return.
fn inhabited(type_) {
  case type_ {
    t.Never -> False
    t.Union(t.Empty) -> False
    t.Promise(_) -> False
    t.List(inner) -> inhabited(inner)
    t.Record(rows) -> inhabited(rows)
    t.RowExtend(_, value, tail) -> inhabited(value) && inhabited(tail)
    t.Fun(_, _, return) -> inhabited(return)
    _ -> True
  }
}

fn peel(scheme, arguments, wanted) {
  case scheme {
    t.Fun(argument, _effect, return) ->
      case match(return, wanted, []) {
        Ok(substitution) ->
          Ok(
            list.reverse([argument, ..arguments])
            |> list.map(substitute(_, substitution, wanted)),
          )
        Error(Nil) -> peel(return, [argument, ..arguments], wanted)
      }
    _ -> Error(Nil)
  }
}

/// One way matching of a builtin return type against a concrete type.
fn match(pattern, concrete, substitution) {
  case pattern, concrete {
    t.Var(key), _ ->
      case list.key_find(substitution, key) {
        Ok(bound) ->
          case bound == concrete {
            True -> Ok(substitution)
            False -> Error(Nil)
          }
        Error(Nil) -> Ok([#(key, concrete), ..substitution])
      }
    t.Integer, t.Integer -> Ok(substitution)
    t.String, t.String -> Ok(substitution)
    t.Binary, t.Binary -> Ok(substitution)
    t.Empty, t.Empty -> Ok(substitution)
    t.List(a), t.List(b) -> match(a, b, substitution)
    t.Record(a), t.Record(b) -> match(a, b, substitution)
    t.Union(a), t.Union(b) -> match(a, b, substitution)
    t.RowExtend(la, a, tail_a), t.RowExtend(lb, b, tail_b) ->
      case la == lb {
        True ->
          case match(a, b, substitution) {
            Ok(substitution) -> match(tail_a, tail_b, substitution)
            Error(Nil) -> Error(Nil)
          }
        False -> Error(Nil)
      }
    t.Fun(a, ea, ra), t.Fun(b, eb, rb) ->
      case match(a, b, substitution) {
        Ok(substitution) ->
          case match(ea, eb, substitution) {
            Ok(substitution) -> match(ra, rb, substitution)
            Error(Nil) -> Error(Nil)
          }
        Error(Nil) -> Error(Nil)
      }
    _, _ -> Error(Nil)
  }
}

fn substitute(type_, substitution, fallback) {
  case type_ {
    t.Var(key) ->
      case list.key_find(substitution, key) {
        Ok(bound) -> bound
        Error(Nil) -> fallback
      }
    t.List(inner) -> t.List(substitute(inner, substitution, fallback))
    t.Record(rows) -> t.Record(substitute(rows, substitution, fallback))
    t.Union(rows) -> t.Union(substitute(rows, substitution, fallback))
    t.RowExtend(label, value, tail) ->
      t.RowExtend(
        label,
        substitute(value, substitution, fallback),
        substitute(tail, substitution, fallback),
      )
    t.Fun(argument, effect, return) ->
      t.Fun(
        substitute(argument, substitution, fallback),
        effect_of(effect, substitution),
        substitute(return, substitution, fallback),
      )
    other -> other
  }
}

/// An effect row that is still free is closed. A builtin argument that can
/// perform an effect, the reducer of a fold for example, is generated as a
/// pure function.
fn effect_of(effect, substitution) {
  case effect {
    t.Var(key) ->
      case list.key_find(substitution, key) {
        Ok(bound) -> bound
        Error(Nil) -> t.Empty
      }
    other -> other
  }
}

/// Rotate a list by a random amount, cheaper than a full shuffle and enough
/// to stop the first matching builtin being the only one ever used.
fn shuffle_once(seed, items) {
  case items {
    [] -> #([], seed)
    _ -> {
      let #(index, seed) = random.int(seed, list.length(items))
      let #(before, after) = list.split(items, index)
      #(list.append(after, before), seed)
    }
  }
}
