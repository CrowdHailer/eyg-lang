# eyg_analysis

Type analysis for [EYG](https://eyg.run) programs.
Infers types for expressions, effects and scope variables.

[![Package Version](https://img.shields.io/hexpm/v/eyg_analysis)](https://hex.pm/packages/eyg_analysis)
[![Hex Docs](https://img.shields.io/badge/hex-docs-ffaff3)](https://hexdocs.pm/eyg_analysis/)

## Usage

```sh
gleam add eyg_analysis
```

This library is open to new type systems and inference algorithms, this means some of the module names are quite specific.
The rest of the examples assume the following imports.

```gleam
import eyg/analysis/inference/levels_j/contextual as infer
import eyg/analysis/type_/binding/error
import eyg/analysis/type_/isomorphic as t
import eyg/ir/tree as ir
```

## Analysis expressions

Analyse a pure, no side effects, expression.

```gleam
pub fn main() {
  let source = ir.let_("x", ir.integer(5), ir.variable("x"))

  let analysis = infer.check(infer.pure(), source)
  let assert [] = infer.all_errors(analysis)
  assert t.Integer == infer.type_(analysis)
}
```

When there are type inconsistencies in a program the inference algorithm will continue.
All errors are found in one pass.
Additionally if a concrete type exists it will also be found.
In this example the value of `x` doesn't effect the expression type and so it is correctly inferred as an integer.

```gleam
let source = ir.let_("x", ir.vacant(), ir.integer(1))

let analysis = infer.check(infer.pure(), source)
assert [#(Nil, error.Todo)] == infer.all_errors(analysis)
assert t.Integer == infer.type_(analysis)
```

Effects can be added to a type checking context.
Here we type check a program in a context with a `Log` effect.

```gleam
let context =
  infer.pure()
  |> infer.with_effect("Log", t.String, t.unit)

let source = ir.call(ir.perform("Log"), [ir.string("hello")])
let analysis = infer.check(context, source)
assert [] == infer.all_errors(analysis)
assert t.Record(t.Empty) == infer.type_(analysis)
```

Note `infer.pure` means that the effect context is closed, only those effects explicitly added are allowed.
Starting with `infer.unpure` allows ANY effect, the effect context is open.
Inferring with `unpure` is still useful as inference checks effects are consistent, i.e. all log effects are called with a string type. The inferred types can be pulled from the returned analysis.

## Tree analysis

The EYG IR allows metadata to attached to every expression in a program.
Using the metadata as an identifier type information at any point in the tree is available.

In this example we manually assign string values to each node in the tree.

```gleam
let source = #(ir.Let("x", #(ir.Integer(10), "b"), #(ir.Vacant, "c")), "a")

let analysis = infer.check(infer.pure(), source)
// The type of the whole expression is unknown.
let assert Ok(type_a) = infer.type_at(analysis, "a")
let assert t.Var(_) = type_a

// The type of the integer literal is correctly inferred.
assert Ok(t.Integer) == infer.type_at(analysis, "b")

// The type of the vacant node is unknown, 
// It's type must be the same as the whole expression because it is the last term in the let expression.
let assert Ok(type_c) = infer.type_at(analysis, "c")
assert type_a == type_c

// We can also inspect the scope at c, which informs us there is a variable in scope containing an integer.
let assert Ok(scope) = infer.scope_at(analysis, "c")
assert Ok(t.Integer) == list.key_find(scope, "x")
```

## Development

```sh
gleam run   # Run the project
gleam test  # Run the tests
```

## Notes

Uses algorithm J with levels https://okmij.org/ftp/ML/generalization.html as a basis.
Records, Unions and Effects are all implemented as row types.

This algorithm is related to algorithm J and is best described by [this summary](https://okmij.org/ftp/ML/generalization.html)
In this case it is combined with opening and closing of effects as described in [section 3.2](https://arxiv.org/pdf/1406.2061.pdf)

Open close is only possible in `Let` and `Var` (also `Builtin`) nodes. This is part of the proof.
A simple demonstration is that open cannot be done in unification because a function arg cannot be opened.
I think there is a generalisation here related to co/contra variance. But I have not rationalised it
Ideally it would be possible to use levels for the closing of effect types, however I think that would require effects being one level deeper than normal type variables. I also how no idea how to demonstrate this as sound.
However, the performance loss for effects is not too bad because when looking for free variables only the type has to be considered and not the whole environment. Not having to enumerate the environment is the main improvement of the levels algorithm.

This algorithm (J) rather than M (and my JM implementation) is unconstrained in the final type.
i.e. types of expressions are found, and then unified with a context. In M the context is typed and unified with each expression as it is reached.
Bottom up allows for easier memoisation. Top down potentially has more focused errors and allows you to specify what type the whole program should have. i.e. (request) -> response for a server.

This algorithm is threads an effect type to save lots of unification with open effect type variables.
Only `Apply` expressions can create an effect.

Types added to metadata are check to see if they would generalise if assigned to a let. This is done by running gen one level above the current expression. This is done so that later unification of rows does not increate the type. The unification of a type in an environment is different to the intrinsict type of an expression.

Effects are not generalised, only closed, so that the field values of the effect are unified where possible.
This choice is mostly for ergonomics.
Schema's could be saved to the env but the will not unify at all, an unification of fields is helpful

I think it is possible to adapt the M algorithm with context typing, to improve editor integration, with closed effects in the meta data. This is only worth doing if we are sure M gives better type errors
