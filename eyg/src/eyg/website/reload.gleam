import eyg/analysis/inference/levels_j/contextual as infer
import eyg/analysis/type_/binding
import eyg/analysis/type_/binding/debug
import eyg/analysis/type_/binding/unify
import eyg/analysis/type_/isomorphic as t
import eygir/annotated
import gleam/io
import gleam/list
import gleam/set
import morph/editable

const state = t.Var(#(True, 0))

const message = t.Union(t.Var(#(True, 1)))

const init = state

fn handle(state, message) {
  t.Fun(state, t.Empty, t.Fun(message, t.Empty, state))
}

fn render(state) {
  t.Fun(state, t.Empty, t.String)
}

pub fn check_against_state(editable, old_state, refs) {
  let b = infer.new_state()
  let #(old_state, b) = binding.instantiate(old_state, 1, b)
  let with_paths = editable.to_annotated(editable, [])
  let source = editable.to_annotated(editable, [])
  let level = 1
  // do infer allows returning top got value, which i don't need?
  let #(tree, b) =
    infer.infer(
      // source
      source,
      // env
      // [],
      // eff
      t.Empty,
      refs,
      level,
      b,
    )

  let paths = annotated.get_annotation(with_paths)
  let info = annotated.get_annotation(tree)
  let assert Ok(info) = list.strict_zip(paths, info)
  let type_errors =
    list.filter_map(info, fn(info) {
      let #(path, #(r, _, _, _)) = info
      case r {
        Ok(_) -> Error(Nil)
        Error(reason) -> Ok(#(path, debug.reason(reason)))
      }
    })
  case type_errors {
    [] -> {
      let #(_, meta) = tree
      let #(_, program, _, _) = meta

      let #(rest, b) = binding.mono(level, b)
      let #(new_state, b) = binding.mono(level, b)

      // Needs to be open for handle etc
      let init_field = t.Record(t.do_rows([#("init", new_state)], rest))

      case unify.unify(init_field, program, level, b) {
        Ok(b) -> {
          // if has init check if init is old or new state type
          let #(migrate_field, upgrade, b) = case
            unify.unify(old_state, new_state, level, b)
          {
            Ok(b) -> {
              #([], False, b)
            }
            Error(_reason) -> {
              let migrate_field = #(
                "migrate",
                t.Fun(old_state, t.Empty, new_state),
              )
              #([migrate_field], True, b)
            }
          }
          let #(new_message, b) = binding.mono(level, b)
          let handle_field = #("handle", handle(new_state, new_message))
          let render_field = #("render", render(new_state))
          let #(remainder, b) = binding.mono(level, b)

          let expect =
            t.do_rows([handle_field, render_field, ..migrate_field], remainder)
          case unify.unify(expect, rest, level, b) {
            Ok(b) -> {
              let state = binding.resolve(new_state, b)
              let state = binding.gen(state, 1, b)
              case all_general(state) {
                True -> Ok(#(state, upgrade))
                False -> Error([#([], "Not all generalisable")])
              }
            }
            Error(reason) -> {
              Error([#([], debug.reason(reason))])
            }
          }
        }
        Error(reason) -> {
          Error([#([], debug.reason(reason))])
        }
      }
    }
    _ -> Error(type_errors)
  }
}

fn all_general(type_) {
  infer.ftv(type_)
  |> set.filter(fn(t) {
    let #(g, _) = t
    !g
  })
  |> set.is_empty
}
