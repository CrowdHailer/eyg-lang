import eyg/analysis/inference/levels_j/contextual as infer
import eyg/analysis/type_/binding
import eyg/analysis/type_/binding/debug as tdebug
import eyg/analysis/type_/binding/error
import eyg/analysis/type_/isomorphic as t
import eyg/runtime/capture
import eyg/runtime/interpreter/state
import eyg/runtime/value as v
import eygir/annotated as a
import gleam/dict.{type Dict}
import gleam/io
import gleam/list
import morph/editable as e
import morph/projection
import spotless/repl/capabilities

pub type Context {
  Context(
    bindings: Dict(Int, binding.Binding),
    scope: List(#(String, binding.Poly)),
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
  Context(bindings, scope, infer.builtins())
}

pub fn empty_environment() {
  Context(dict.new(), [], infer.builtins())
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
  let #(eff, bindings) = capabilities.handler_type(bindings)
  let #(bindings, _top_type, _top_eff, tree) =
    infer.do_infer(source, scope, eff, dict.new(), 0, bindings)
  let #(_, types) = a.strip_annotation(tree)
  let #(_, paths) = a.strip_annotation(e.to_annotated(editable, []))
  #(bindings, list.zip(paths, types))
}

pub fn env_at(projection, root_env, at) {
  let #(bindings, pairs) = analyse(projection, root_env)
  case list.key_find(pairs, at) {
    Ok(#(_result, _type, _eff, env)) -> env
    Error(Nil) -> {
      io.debug(#("didn't find env", at))
      let Context(bindings, tenv, ..) = root_env
      tenv
    }
  }
}

pub fn type_at(projection, root_env) {
  let #(bindings, pairs) = analyse(projection, root_env)
  let path = projection.path_to_zoom(projection.1, [])
  case list.key_find(pairs, path) {
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

// TODO effects are not put into the tree either that needs to be done or we walk up the tree
pub fn effect_at(_projection, context) {
  let Context(bindings, _, _) = context
  // let path = projection.path_to_zoom(projection.1, [])
  // io.debug(pairs)
  // case list.key_find(pairs, path) {
  //   Ok(#(_result, _type, eff, _env)) -> Ok(binding.resolve(eff, bindings))
  //   Error(Nil) -> {
  //     io.debug(#("didn't find type", path))
  //     Error(Nil)
  //   }
  // }
  let #(eff, _bindings) = capabilities.handler_type(bindings)
  Ok(eff)
}

pub fn effect_fields(projection, root_env) {
  case effect_at(projection, root_env) {
    Ok(eff_type) -> effects(eff_type, [])
    eff -> []
  }
}

fn effects(t, acc) {
  case t {
    t.EffectExtend(label, types, rest) ->
      effects(rest, [#(label, types), ..acc])
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
    #(path, tdebug.render_reason(reason))
  })
}
