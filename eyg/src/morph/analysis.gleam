import eyg/analysis/inference/levels_j/contextual as infer
import eyg/analysis/type_/binding
import eyg/analysis/type_/binding/debug
import eyg/analysis/type_/binding/error
import eyg/analysis/type_/isomorphic as t
import eyg/runtime/capture
import eyg/runtime/interpreter/state
import eyg/runtime/value as v
import eygir/annotated as a
import gleam/dict.{type Dict}
import gleam/int
import gleam/io
import gleam/list
import gleam/string
import morph/editable as e
import morph/projection
import spotless/repl/capabilities

pub type Context {
  Context(
    bindings: Dict(Int, binding.Binding),
    scope: List(#(String, binding.Poly)),
    references: Dict(String, binding.Poly),
    builtins: List(#(String, binding.Poly)),
  )
}

pub type Analysis =
  #(
    Dict(Int, binding.Binding),
    List(
      #(
        List(Int),
        #(
          Result(Nil, error.Reason),
          binding.Mono,
          binding.Mono,
          List(#(String, binding.Poly)),
        ),
      ),
    ),
  )

pub fn within_environment(runtime_env) {
  let #(bindings, scope) = env_to_tenv(runtime_env)
  io.debug("need referencesss")
  Context(bindings, scope, dict.new(), infer.builtins())
}

pub fn empty_environment() {
  io.debug("need referencesss")
  Context(dict.new(), [], dict.new(), infer.builtins())
}

// use capture because we want efficient ability to get to continuations
fn value_to_type(value, bindings) {
  case value {
    v.Closure(_, _, _) -> {
      let #(#(_, #(_, type_, _, _)), bindings) =
        capture.capture(value)
        |> infer.infer(t.Empty, dict.new(), 0, bindings)
      #(binding.gen(type_, -1, bindings), bindings)
    }
    v.Binary(_) -> #(t.Binary, bindings)
    v.Integer(_) -> #(t.Integer, bindings)
    v.Str(_) -> #(t.String, bindings)
    v.LinkedList([]) -> {
      let level = 0
      let #(var, bindings) = binding.poly(level, bindings)
      #(t.List(var), bindings)
    }
    v.LinkedList([item, ..]) -> {
      let #(item_type, bindings) = value_to_type(item, bindings)
      #(t.List(item_type), bindings)
    }
    v.Record(fields) -> {
      let #(bindings, fields) =
        list.map_fold(fields, bindings, fn(bindings, field) {
          let #(label, value) = field
          let #(type_, bindings) = value_to_type(value, bindings)
          #(bindings, #(label, type_))
        })
      let rows =
        list.fold_right(fields, t.Empty, fn(rest, field) {
          let #(label, type_) = field
          t.RowExtend(label, type_, rest)
        })
      #(t.Record(rows), bindings)
    }
    v.Tagged(label, value) -> {
      let #(type_, bindings) = value_to_type(value, bindings)
      let level = 0
      let #(var, bindings) = binding.poly(level, bindings)

      #(t.Union(t.RowExtend(label, type_, var)), bindings)
    }
    v.Partial(v.Cons, args) -> panic as "type partial"
    v.Partial(v.Match(_), [_, _]) -> {
      // let #(var, bindings) = binding.poly(level, bindings)
      // let #(var, bindings) = binding.poly(level, bindings)
      let #(#(_, #(_, type_, _, _)), bindings) =
        capture.capture(value)
        |> infer.infer(t.Empty, dict.new(), 0, bindings)
      #(binding.gen(type_, -1, bindings), bindings)
    }
    v.Promise(_) -> panic as "do promises need to be specific type"
    _ -> {
      // console.log(value)
      let level = 0
      let #(var, bindings) = binding.poly(level, bindings)
    }
  }
}

// TODO add a small initial script BUT i want std lib etc
// Vars together for environment

fn env_to_tenv(env: state.Env(Nil)) {
  let bindings = infer.new_state()

  list.map_fold(env.scope, bindings, fn(bindings, pair) {
    let #(var, value) = pair
    let #(type_, bindings) = value_to_type(value, bindings)
    #(bindings, #(var, type_))
  })
}

pub fn scope_vars(projection, root_env) {
  env_at(projection, root_env, projection.path_to_zoom(projection.1, []))
}

pub fn analyse(projection, context) -> Analysis {
  let Context(bindings, scope, ..) = context
  let editable = projection.rebuild(projection)
  let source = e.to_expression(editable)
  // TODO these needs to depend better on eff but is blocked by proper reuse of the analysis work
  let #(eff, bindings) = capabilities.handler_type(bindings)
  let #(bindings, _top_type, _top_eff, tree) =
    infer.do_infer(source, scope, eff, context.references, 0, bindings)
  let #(_, types) = a.strip_annotation(tree)
  let #(_, paths) = a.strip_annotation(e.to_annotated(editable, []))
  #(bindings, list.zip(paths, types))
}

pub fn print(analysis) {
  let #(bindings, pairs) = analysis
  list.map(pairs, fn(pair) {
    let #(rev, #(result, type_, _eff, _scope)) = pair
    let path = list.reverse(rev)
    let path = "[" <> string.join(list.map(path, int.to_string), ",") <> "]"
    let t = case result {
      Ok(Nil) -> debug.mono(binding.resolve(type_, bindings))
      Error(reason) -> debug.reason(reason)
    }
    path <> " " <> t
  })
  |> list.map(io.println)
}

pub fn env_at(projection, root_env, path) {
  let #(bindings, pairs) = analyse(projection, root_env)
  case list.key_find(pairs, list.reverse(path)) {
    Ok(#(_result, _type, _eff, env)) -> env
    Error(Nil) -> {
      io.debug(#("didn't find env", path))
      let Context(bindings, tenv, ..) = root_env
      tenv
    }
  }
}

pub fn type_at(projection, root_env) {
  let analysis = analyse(projection, root_env)
  do_type_at(analysis, projection)
}

pub fn do_type_at(analysis, projection: #(_, _)) {
  let #(bindings, pairs) = analysis
  let path = projection.path(projection)
  // tests to remove this
  // io.debug(path)
  // io.debug(pairs |> list.map(fn(x: #(_, #(_, _, _, _))) { #(x.0, { x.1 }.1) }))
  // TODO a shared info at would be a useful utility to ensure path reversing done correctly
  case list.key_find(pairs, list.reverse(path)) {
    Ok(#(_result, type_, _eff, _env)) -> Ok(binding.resolve(type_, bindings))
    Error(Nil) -> {
      io.debug(#("didn't find type", path))
      Error(Nil)
    }
  }
}

fn do_count_args(type_, acc) {
  case type_ {
    t.Fun(_, _, return) -> do_count_args(return, acc + 1)
    _ -> acc
  }
}

pub fn count_args(projection, root_env) {
  case type_at(projection, root_env) {
    Ok(t.Fun(_, _, return)) -> Ok(do_count_args(return, 1))
    _ -> Error(Nil)
  }
}

pub fn type_fields(projection, root_env) {
  case type_at(projection, root_env) {
    Ok(t.Record(row_type)) -> rows(row_type, [])
    _ -> []
  }
}

pub fn type_variants(projection, root_env) {
  case type_at(projection, root_env) {
    Ok(t.Union(row_type)) -> rows(row_type, [])
    _ -> []
  }
}

fn rows(t, acc) {
  case t {
    t.RowExtend(label, value, rest) -> rows(rest, [#(label, value), ..acc])
    _ -> list.reverse(acc)
  }
}

pub fn type_errors(analysis) {
  let #(_bindings, pairs) = analysis
  list.filter_map(pairs, fn(r) {
    let #(rev, #(r, _, _, _)) = r
    case r {
      Ok(_) -> Error(Nil)
      Error(reason) -> Ok(#(list.reverse(rev), reason))
    }
  })
  |> list.map(fn(pair) {
    let #(path, reason) = pair
    #(path, reason)
  })
}