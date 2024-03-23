import gleam/dict
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import glance
import scintilla/value as v
import scintilla/reason as r
import scintilla/interpreter/runner

pub fn empty(modules) {
  #(dict.new(), modules)
}

pub fn declare(declaration, state) {
  let #(scope, modules) = state
  case declaration {
    glance.AttributeEnum(_) -> Error(r.Unsupported("attributes"))
    glance.ImportEnum(import_) -> {
      let glance.Import(module, alias, _types, values) = import_
      let binding = case alias {
        Some(label) -> label
        None -> {
          let assert [label, ..] = list.reverse(string.split(module, "/"))
          label
        }
      }
      let unqualified =
        list.map(values, fn(v) {
          let glance.UnqualifiedImport(field, label) = v
          let label = option.unwrap(label, field)
          #(field, label)
        })
      case dict.get(modules, module) {
        Ok(module) -> {
          let scope = dict.insert(scope, binding, v.Module(module))
          let scope =
            list.fold(unqualified, scope, fn(scope, extra) {
              let #(field, name) = extra
              //   let assert Ok(value) = state.access_module(module, field)

              //   dict.insert(scope, name, value)
              todo as "do I want to access all these fields eager"
            })
          Ok(#(scope, modules))
        }
        Error(Nil) -> {
          Error(r.UnknownModule(module))
        }
      }
    }
    _ -> panic as "unsupported in repl"
  }
}

pub fn exec(statements, state) {
  let #(scope, _modules) = state
  case runner.exec(statements, scope) {
    Ok(value) -> Ok(#(value, state))
    Error(reason) -> Error(reason)
  }
}
