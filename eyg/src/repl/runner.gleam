import gleam/dict.{type Dict}
import gleam/float
import gleam/int
import gleam/io
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result.{try}
import gleam/string
import glance as g
import scintilla/value.{type Value} as v
import scintilla/reason as r
import scintilla/cast
import scintilla/interpreter/state
import repl/reader

pub type State =
  #(Dict(String, Value), Dict(String, g.Module))

pub fn init(scope, modules) {
  #(scope, modules)
}

// could return bindings not env
pub fn read(declaration, state) {
  let #(scope, modules) = state
  case declaration {
    reader.CustomType(variants) -> {
      let scope =
        list.fold(variants, scope, fn(scope, variant) {
          let #(name, fields) = variant
          let value = case fields {
            [] -> v.R(name, [])
            _ -> v.Constructor(name, fields)
          }
          dict.insert(scope, name, value)
        })
      let state = #(scope, modules)
      Ok(#(None, state))
    }
    reader.Constant(name, exp) -> {
      let #(return, logs) =
        live_loop(state.next(state.eval(exp, scope, [])), [])
      case return {
        Ok(value) -> {
          let scope = dict.insert(scope, name, value)
          let state = #(scope, modules)
          Ok(#(Some(value), state))
        }
        Error(#(reason, _, _)) -> Error(reason)
      }
    }
    reader.Function(name, parameters, body) -> {
      let value = v.NamedClosure(parameters, body, scope)
      let scope = dict.insert(scope, name, value)
      let state = #(scope, modules)
      Ok(#(Some(value), state))
    }
    reader.Statements(statements) -> {
      let #(return, logs) = live_exec(statements, scope)
      case
        return
        |> result.map_error(fn(e: #(_, _, _)) { e.0 })
      {
        Ok(value) -> Ok(#(Some(value), state))
        Error(r.Finished(scope)) -> {
          let state = #(scope, modules)
          Ok(#(None, state))
        }
        Error(reason) -> Error(reason)
      }
    }
    reader.Import(_, _, _) -> panic as "import not supported"
  }
}

// TODO deduplicate with read
pub fn read_live(term, state) {
  todo
  // todo
  // let #(scope, modules) = state
  // case term {
  //   reader.Import(module, binding, unqualified) -> {
  //     case dict.get(modules, module) {
  //       Ok(module) -> {
  //         let scope = dict.insert(scope, binding, v.Module(module))
  //         let scope =
  //           list.fold(unqualified, scope, fn(scope, extra) {
  //             let #(field, name) = extra
  //             let assert Ok(value) = state.access_module(module, field)
  //             dict.insert(scope, name, value)
  //           })
  //         Ok(#(None, #(scope, modules)))
  //       }
  //       Error(Nil) -> {
  //         Error(r.UnknownModule(module))
  //       }
  //     }
  //   }
  //   reader.CustomType(variants) -> {
  //     let scope =
  //       list.fold(variants, scope, fn(scope, variant) {
  //         let #(name, fields) = variant
  //         let value = case fields {
  //           [] -> v.R(name, [])
  //           _ -> v.Constructor(name, fields)
  //         }
  //         dict.insert(scope, name, value)
  //       })
  //     let state = #(scope, modules)
  //     Ok(#(None, state))
  //   }
  //   reader.Constant(name, exp) -> {
  //     let #(return, logs) =
  //       live_loop(state.next(state.eval(exp, scope, [])), [])
  //     case return {
  //       Ok(value) -> {
  //         let scope = dict.insert(scope, name, value)
  //         let state = #(scope, modules)
  //         Ok(#(Some(#(value, logs)), state))
  //       }
  //       Error(#(reason, _, _)) -> Error(reason)
  //     }
  //   }
  //   reader.Function(name, parameters, body) -> {
  //     let value = v.NamedClosure(parameters, body, scope)
  //     let scope = dict.insert(scope, name, value)
  //     let state = #(scope, modules)
  //     Ok(#(Some(#(value, [])), state))
  //   }
  //   reader.Statements(statements) -> {
  //     let #(return, logs) = live_exec(statements, scope)
  //     case
  //       return
  //       |> result.map_error(fn(e: #(_, _, _)) { e.0 })
  //     {
  //       Ok(value) -> Ok(#(Some(#(value, logs)), state))
  //       Error(r.Finished(scope)) -> {
  //         let state = #(scope, modules)
  //         Ok(#(None, state))
  //       }
  //       Error(reason) -> Error(reason)
  //     }
  //   }
  // }
}

pub fn live_exec(statements, env) {
  live_loop(state.next(state.push_statements(statements, env, [])), [])
}

pub fn live_loop(next, logs) {
  case next {
    state.Loop(c, e, ks) -> {
      let logs = case c, ks {
        state.V(v), [state.Assign(p), ..] -> {
          case state.assign_pattern(dict.new(), p, v) {
            Ok(env) -> {
              let new = dict.to_list(env)
              [new, ..logs]
            }
            _ -> logs
          }
        }
        state.V(v), [state.Apply(func, label, [], args), ..] -> {
          let args = list.reverse([g.Field(label, v), ..args])
          case state.call(func, args, dict.new(), []) {
            Ok(#(_, env, _)) -> [dict.to_list(env), ..logs]
            _ -> logs
          }
        }
        // I want to do this with a general apply statement but can't work out how to clear existing env from captured fn
        state.V(v), [state.BuildSubjects([], values, clauses) as k, ..] -> {
          case state.apply(v, dict.new(), k, []) {
            Ok(#(_, env, _)) -> [dict.to_list(env), ..logs]
            _ -> logs
          }
        }
        _, _ -> logs
      }
      live_loop(state.step(c, e, ks), logs)
    }
    state.Break(result) -> #(result, list.reverse(logs))
  }
}
