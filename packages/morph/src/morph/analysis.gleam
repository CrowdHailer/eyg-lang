import eyg/analysis/inference/levels_j/contextual as infer
import eyg/analysis/type_/binding
import eyg/analysis/type_/binding/error
import eyg/analysis/type_/binding/unify
import eyg/analysis/type_/isomorphic as t
import eyg/interpreter/capture
import eyg/interpreter/value as v
import eyg/ir/tree as ir
import gleam/dict.{type Dict}
import gleam/io
import gleam/list
import gleam/string
import morph/editable as e
import morph/projection

pub type References =
  Dict(String, binding.Poly)

pub type Index =
  List(#(String, Int, String))

pub type Context {
  Context(
    bindings: Dict(Int, binding.Binding),
    scope: List(#(String, binding.Poly)),
    effects: List(#(String, #(binding.Mono, binding.Mono))),
    references: References,
    index: Index,
  )
}

pub type Analysis {

  Analysis(
    bindings: Dict(Int, binding.Binding),
    inferred: List(
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
    context: Context,
  )
}

pub fn context() {
  Context(dict.new(), [], [], dict.new(), [])
}

pub fn within_environment(runtime_env, meta) {
  let #(bindings, scope) = env_to_tenv(runtime_env, meta)
  Context(bindings, scope, [], dict.new(), [])
}

pub fn with_references(context, references) {
  Context(..context, references: references)
}

pub fn with_effects(context, effects) {
  Context(..context, effects: effects)
}

pub fn with_index(context, index) {
  Context(..context, index: index)
}

// use capture because we want efficient ability to get to continuations
pub fn value_to_type(value, bindings, meta: t) {
  case value {
    v.Closure(_, _, _) -> {
      let #(#(_, #(_, type_, _, _)), bindings) =
        capture.capture(value, meta)
        |> infer.infer(t.Empty, dict.new(), 0, bindings)
      #(binding.gen(type_, -1, bindings), bindings)
    }
    v.Binary(_) -> #(t.Binary, bindings)
    v.Integer(_) -> #(t.Integer, bindings)
    v.String(_) -> #(t.String, bindings)
    v.LinkedList([]) -> {
      let level = 0
      let #(var, bindings) = binding.poly(level, bindings)
      #(t.List(var), bindings)
    }
    v.LinkedList([item, ..]) -> {
      let #(item_type, bindings) = value_to_type(item, bindings, meta)
      #(t.List(item_type), bindings)
    }
    v.Record(fields) -> {
      let fields = dict.to_list(fields)
      let #(bindings, fields) =
        list.map_fold(fields, bindings, fn(bindings, field) {
          let #(label, value) = field
          let #(type_, bindings) = value_to_type(value, bindings, meta)
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
      let #(type_, bindings) = value_to_type(value, bindings, meta)
      let level = 0
      let #(var, bindings) = binding.poly(level, bindings)

      #(t.Union(t.RowExtend(label, type_, var)), bindings)
    }
    v.Partial(v.Builtin(id), args) -> {
      case list.key_find(infer.builtins(), id) {
        Ok(func) -> {
          let #(func, bindings) = binding.instantiate(func, 1, bindings)
          let #(func, bindings) =
            list.fold(args, #(func, bindings), fn(acc, arg) {
              let level = 1
              let #(func, bindings) = acc
              let #(t_arg, bindings) = value_to_type(arg, bindings, meta)
              let #(t_arg, bindings) = binding.instantiate(t_arg, 1, bindings)

              let #(ty_ret, bindings) = binding.mono(level, bindings)
              let #(test_eff, bindings) = binding.mono(level, bindings)

              let bindings = case
                unify.unify(
                  t.Fun(t_arg, test_eff, ty_ret),
                  func,
                  level,
                  bindings,
                )
              {
                Ok(bindings) -> bindings
                Error(_reason) -> bindings
              }
              #(ty_ret, bindings)
            })
          #(binding.gen(func, 1, bindings), bindings)
        }
        Error(Nil) -> panic as "where did this builtin come from"
      }
    }
    v.Partial(_node, _args) | v.Promise(_) -> {
      io.println(string.inspect(value))
      panic as "These value cannot be cast to a type, they should not occur in the standard editable programs"
    }
  }
}

pub fn env_to_tenv(scope, meta) {
  let bindings = infer.new_state()

  list.map_fold(scope, bindings, fn(bindings, pair) {
    let #(var, value) = pair
    let #(type_, bindings) = value_to_type(value, bindings, meta)
    #(bindings, #(var, type_))
  })
}

pub fn scope_vars(projection: projection.Projection, analysis) {
  env_at(analysis, projection.path_to_zoom(projection.1, []))
}

pub fn do_analyse(editable, context) -> Analysis {
  let Context(bindings, scope, effects, ..) = context
  let eff =
    effects
    |> list.fold(t.Empty, fn(acc, new) {
      let #(label, #(lift, reply)) = new
      t.EffectExtend(label, #(lift, reply), acc)
    })

  let source = e.to_annotated(editable, [])
  let #(bindings, _top_type, _top_eff, tree) =
    infer.do_infer(source, scope, eff, context.references, 0, bindings)
  let types = ir.get_annotation(tree)
  let paths = ir.get_annotation(e.to_annotated(editable, []))
  Analysis(bindings, list.zip(paths, types), context)
}

// pub fn print(analysis) {
//   let #(bindings, pairs) = analysis
//   list.map(pairs, fn(pair) {
//     let #(rev, #(result, type_, _eff, _scope)) = pair
//     let path = list.reverse(rev)
//     let path = "[" <> string.join(list.map(path, int.to_string), ",") <> "]"
//     let t = case result {
//       Ok(Nil) -> debug.mono(binding.resolve(type_, bindings))
//       Error(reason) -> debug.reason(reason)
//     }
//     path <> " " <> t
//   })
//   |> list.map(io.println)
// }

fn env_at(analysis, path) {
  let Analysis(inferred:, ..) = analysis
  case list.key_find(inferred, list.reverse(path)) {
    Ok(#(_result, _type, _eff, env)) -> env
    Error(Nil) -> {
      io.debug(#("didn't find env", path))
      // let Context(bindings, tenv, ..) = root_env
      // tenv
      []
    }
  }
}

pub fn do_type_at(analysis, projection: #(_, _)) {
  let Analysis(bindings:, inferred:, ..) = analysis
  let path = projection.path(projection)
  // tests to remove this
  // io.debug(path)
  // io.debug(inferred |> list.map(fn(x: #(_, #(_, _, _, _))) { #(x.0, { x.1 }.1) }))
  // TODO a shared info at would be a useful utility to ensure path reversing done correctly
  case list.key_find(inferred, list.reverse(path)) {
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

pub fn count_args(projection, analysis) {
  case do_type_at(analysis, projection) {
    Ok(t.Fun(_, _, return)) -> Ok(do_count_args(return, 1))
    _ -> Error(Nil)
  }
}

pub fn type_fields(projection, analysis) {
  case do_type_at(analysis, projection) {
    Ok(t.Record(row_type)) -> rows(row_type, [])
    _ -> []
  }
}

pub fn type_variants(projection, analysis) {
  case do_type_at(analysis, projection) {
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
  let Analysis(inferred:, ..) = analysis
  list.filter_map(inferred, fn(r) {
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
