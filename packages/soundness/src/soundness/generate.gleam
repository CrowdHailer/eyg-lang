//// Generates random EYG programs.
////
//// The programs are well scoped, every variable is bound, but they are not
//// well typed. The analysis is the oracle that decides which of them count,
//// so a generated program that does not type check is simply discarded.
//// Every reference-free expression form accepted by analysis is reachable.
//// Vacant is deliberately excluded because analysis rejects it as incomplete,
//// and references need resolution before they can be evaluated. Primitives
//// and builtins may be bare, partially applied, or fully applied.

import eyg/analysis/inference/levels_j/contextual as j
import eyg/ir/tree as ir
import gleam/int
import gleam/list
import soundness/random

const fields = ["a", "b", "c"]

const tags = ["Ok", "Error", "Some"]

const effects = ["Log", "Ask"]

/// Every builtin the analysis has a type for, with its arity.
pub fn builtins() {
  list.filter_map(j.builtins(), fn(entry) {
    let #(name, type_) = entry
    case j.count_args(type_) {
      Ok(arity) -> Ok(#(name, arity))
      Error(Nil) -> Error(Nil)
    }
  })
}

/// Generate a program of roughly the requested size.
pub fn program(seed, size) {
  expression(seed, [], size, 0)
}

fn expression(seed, scope, size, depth) {
  case size <= 1 {
    True -> leaf(seed, scope)
    False -> branch(seed, scope, size, depth)
  }
}

fn leaf(seed, scope) {
  let choices = case scope {
    [] -> constants()
    _ -> [#(6, Var), ..constants()]
  }
  let #(choice, seed) = random.weighted(seed, choices)
  case choice {
    Var -> {
      let #(label, seed) = random.pick(seed, scope)
      #(ir.variable(label), seed)
    }
    Int -> {
      let #(value, seed) = random.int(seed, 5)
      #(ir.integer(value), seed)
    }
    Str -> {
      let #(value, seed) = random.pick(seed, ["", "hey"])
      #(ir.string(value), seed)
    }
    Bin -> #(ir.binary(<<0, 1>>), seed)
    EmptyList -> #(ir.tail(), seed)
    EmptyRecord -> #(ir.empty(), seed)
  }
}

fn constants() {
  [#(4, Int), #(2, Str), #(1, Bin), #(2, EmptyList), #(2, EmptyRecord)]
}

/// Every IR primitive that is not a literal or a general language form.
///
/// The number is its full arity. Generation chooses any arity from zero up to
/// this number, so bare and partially applied primitives are reachable too.
pub fn primitives() {
  [
    #(ir.cons(), 2),
    #(ir.extend("a"), 2),
    #(ir.select("a"), 1),
    #(ir.overwrite("a"), 2),
    #(ir.tag("Ok"), 1),
    #(ir.case_("Ok"), 3),
    #(ir.nocases(), 1),
    #(ir.perform("Log"), 1),
    #(ir.handle("Log"), 2),
  ]
}

type Leaf {
  Var
  Int
  Str
  Bin
  EmptyList
  EmptyRecord
}

type Form {
  Function
  Application
  Binding
  Applied(ir.Expression(Nil), Int)
  AppliedBuiltin
}

fn forms() {
  let primitives =
    list.map(primitives(), fn(primitive) {
      let #(expression, arity) = primitive
      #(3, Applied(expression.0, arity))
    })
  list.append(
    [
      #(6, Function),
      #(8, Application),
      #(6, Binding),
      #(10, AppliedBuiltin),
    ],
    primitives,
  )
}

fn branch(seed, scope, size, depth) {
  let #(form, seed) = random.weighted(seed, forms())
  case form {
    Function -> {
      let label = "x" <> int.to_string(depth)
      let #(body, seed) =
        expression(seed, [label, ..scope], size - 1, depth + 1)
      #(ir.lambda(label, body), seed)
    }
    Application -> {
      let #(func, seed) = expression(seed, scope, size / 2, depth + 1)
      let #(arg, seed) = expression(seed, scope, size / 2, depth + 1)
      #(ir.apply(func, arg), seed)
    }
    Binding -> {
      let label = "x" <> int.to_string(depth)
      let #(value, seed) = expression(seed, scope, size / 2, depth + 1)
      let #(body, seed) =
        expression(seed, [label, ..scope], size / 2, depth + 1)
      #(ir.let_(label, value, body), seed)
    }
    Applied(expression, arity) -> {
      let #(expression, seed) = relabel(seed, expression)
      let #(arity, seed) = random.int(seed, arity + 1)
      applied(seed, scope, size, depth, #(expression, Nil), arity)
    }
    AppliedBuiltin -> {
      let #(#(name, arity), seed) = random.pick(seed, builtins())
      let #(arity, seed) = random.int(seed, arity + 1)
      applied(seed, scope, size, depth, ir.builtin(name), arity)
    }
  }
}

// Nodes are generated with a fixed label so that the whole set of them can be
// listed as constants, the label is replaced with a random one here.
fn relabel(seed, expression) {
  case expression {
    ir.Extend(_) -> {
      let #(label, seed) = random.pick(seed, fields)
      #(ir.Extend(label), seed)
    }
    ir.Select(_) -> {
      let #(label, seed) = random.pick(seed, fields)
      #(ir.Select(label), seed)
    }
    ir.Overwrite(_) -> {
      let #(label, seed) = random.pick(seed, fields)
      #(ir.Overwrite(label), seed)
    }
    ir.Tag(_) -> {
      let #(label, seed) = random.pick(seed, tags)
      #(ir.Tag(label), seed)
    }
    ir.Case(_) -> {
      let #(label, seed) = random.pick(seed, tags)
      #(ir.Case(label), seed)
    }
    ir.Perform(_) -> {
      let #(label, seed) = random.pick(seed, effects)
      #(ir.Perform(label), seed)
    }
    ir.Handle(_) -> {
      let #(label, seed) = random.pick(seed, effects)
      #(ir.Handle(label), seed)
    }
    other -> #(other, seed)
  }
}

fn applied(seed, scope, size, depth, func, arity) {
  let budget = size / { arity + 1 }
  case arity <= 0 {
    True -> #(func, seed)
    False -> {
      let #(arg, seed) = expression(seed, scope, budget, depth + 1)
      applied(seed, scope, size, depth, ir.apply(func, arg), arity - 1)
    }
  }
}
