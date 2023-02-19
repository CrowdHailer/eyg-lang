import gleam/io
import gleam/list
import gleam/map
import gleam/option.{None, Some}
import eygir/expression as e
import eyg/runtime/interpreter as r
import eyg/analysis/inference
import eyg/analysis/typ as t
import gleam/result

pub fn binary(value) {
  e.Apply(e.Tag("Binary"), e.Binary(value))
}

pub fn integer(value) {
  e.Apply(e.Tag("Integer"), e.Integer(value))
}

pub fn variable(label) {
  e.Apply(e.Tag("Variable"), e.Binary(label))
}

// TODO decide func fun lambda, use constants for keys
pub fn lambda(param, body) {
  e.Apply(
    e.Tag("Lambda"),
    e.Apply(
      e.Apply(e.Extend("label"), e.Binary(param)),
      e.Apply(e.Apply(e.Extend("body"), body), e.Empty),
    ),
  )
}

// TODO built in Type and AST types as can't do recursive
// TODO k in provider eval
// TODO add a Must function that handles runtime things to preeval
// static.preeval/infer/shrink/alpha/beta returctions
// TODO json encode decode available in std lib for universal app
// preeval drop through implentation
// TODO test below

// Expand only really needed because can't remove provider from static analysis
// Could make an interpretr that assumes never a provider.
// But need to stack can I statically always remove all providers? I guess lazy builin it possible
fn id(x) {
  r.Value(x)
}

fn step(path, i) {
  list.append(path, [i])
}

// TODO deduplicate fn
fn field(row: t.Row(a), label) {
  case row {
    t.Open(_) | t.Closed -> Error(Nil)
    t.Extend(l, t, _) if l == label -> Ok(t)
    t.Extend(_, _, tail) -> field(tail, label)
  }
}

const r_unit = r.Record([])

pub fn type_to_language_term(type_) {
  case type_ {
    t.Unbound(i) -> r.Tagged("Unbound", r.Integer(i))
    t.Integer -> r.Tagged("Integer", r_unit)
    t.Binary -> r.Tagged("Binary", r_unit)
    t.LinkedList(item) -> r.Tagged("List", type_to_language_term(item))
    t.Fun(from, effects, to) -> {
      let from = type_to_language_term(from)
      let to = type_to_language_term(to)
      r.Tagged("Lambda", r.Record([#("from", from), #("to", to)]))
    }
    t.Record(row) -> r.Tagged("Record", row_to_language_term(row))
    t.Union(row) -> r.Tagged("Union", row_to_language_term(row))
  }
}

fn row_to_language_term(row) {
  todo("row_to_language_term")
}

pub fn language_term_to_expression(term) -> e.Expression {
  assert r.Tagged(node, inner) = term
  case node {
    "Variable" -> {
      assert r.Binary(value) = inner
      e.Variable(value)
    }
    "Lambda" -> {
      assert r.Record(fields) = inner
      assert Ok(r.Binary(param)) = list.key_find(fields, "label")
      assert Ok(body) = list.key_find(fields, "body")
      e.Lambda(param, language_term_to_expression(body))
    }
    "Binary" -> {
      assert r.Binary(value) = inner
      e.Binary(value)
    }
    "Integer" -> {
      assert r.Integer(value) = inner
      e.Integer(value)
    }
  }
}

pub fn expand(generator, inferred, path) {
  try fit =
    inference.type_of(inferred, path)
    |> result.map_error(fn(reason) {
      io.debug(path)
      todo("this inf error")
    })
  try needed = case fit {
    t.Union(row) ->
      // TODO ordered fields fn
      field(row, "Ok")
      |> result.map_error(fn(_) { "no Ok field" })

    _ -> Error("not a union")
  }

  io.debug(#("needed", needed))

  assert r.Value(result) =
    r.eval_call(
      generator,
      type_to_language_term(needed),
      fn(_, _) { r.Abort(todo("lets not get nested yet")) },
      id,
    )

  // TODO return runtime result, static analysis should be part of static tooling
  assert r.Tagged(tag, value) = result
  case tag {
    "Ok" -> {
      let generated = language_term_to_expression(value)
      io.debug(#("generated", generated))
      let inferred = inference.infer(map.new(), generated, needed, t.Closed)
      // Maybe sound inference is part of expand i.e. static
      io.debug(inference.sound(inferred))
      let code = case inference.sound(inferred) {
        Ok(Nil) -> e.Apply(e.Tag("Ok"), generated)
        Error(_) -> e.Apply(e.Tag("Error"), e.unit)
      }
      Ok(code)
    }
  }
}

// =------------------------

// TODO call pre eval
fn do_expand(source, inferred, path, env) {
  case source {
    e.Variable(label) -> Ok(e.Variable(label))
    e.Lambda(label, body) -> {
      try body = do_expand(body, inferred, [0, ..path], env)
      Ok(e.Lambda(label, body))
    }
    e.Apply(func, argument) -> {
      try func = do_expand(func, inferred, [0, ..path], env)
      try argument = do_expand(argument, inferred, [1, ..path], env)
      Ok(e.Apply(func, argument))
    }
    e.Let(label, definition, body) -> {
      try definition =
        do_expand(
          definition,
          inferred,
          [0, ..path],
          [#(label, definition), ..env],
        )
      try body = do_expand(body, inferred, [1, ..path], env)
      Ok(e.Let(label, definition, body))
    }

    e.Cons -> Ok(e.Cons)
    e.Tail -> Ok(e.Tail)

    e.Integer(value) -> Ok(e.Integer(value))
    e.Binary(value) -> Ok(e.Binary(value))
    e.Vacant -> Ok(e.Vacant)
    e.Empty -> Ok(e.Empty)
    e.Extend(label) -> Ok(e.Extend(label))
    e.Select(label) -> Ok(e.Select(label))
    e.Overwrite(label) -> Ok(e.Overwrite(label))
    e.Tag(label) -> Ok(e.Tag(label))
    e.Case(label) -> Ok(e.Case(label))
    e.NoCases -> Ok(e.NoCases)
    e.Perform(label) -> Ok(e.Perform(label))
    e.Handle(label) -> Ok(e.Handle(label))
    // e.Let(label, value, then) -> {
    //   let value = do_expand(value, inferred, step(path, 0), env)
    //   //   assert r.Value(term) =
    //   //     r.eval(value, env, id)
    //   //     |> io.debug
    //   let then =
    //     do_expand(then, inferred, step(path, 1), [#(label, value), ..env])
    //   e.Let(label, value, then)
    // }
    // e.Lambda(param, body) -> e.Lambda(param, body)
    // DO we always want a fn probably not
    e.Provider(generator) -> {
      // TODO expand should probably find something callable for generator, rather than an AST
      // and at this point we do shrink a
      // pass through new runtime value eval every thing with my parameters kind in the env
      // slight eval
      // OORR put path info on interpreter, probably good.
      // pass Waiting or normal runtime through.
      io.debug(env)
      // TODO needs variables available to the generator
      assert r.Value(generator) =
        r.eval(generator, [], fn(_, _) { todo("also nested avoid") }, id)
        |> io.debug

      // expand needs a runtime value, with env captured, so semantics of env management don't need to be understood
      // TODO totally sensible that runtime value is returned and only in precompile do we put it back to expression
      // inference could be completly separate rerun, but that's in efficient and bad for debugging.
      //   need env at the time
      expand(generator, inferred, list.reverse(path))
    }
  }
}

pub fn pre_eval(source, inferred) {
  do_expand(source, inferred, [], [])
}
