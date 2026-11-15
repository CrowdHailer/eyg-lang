//// Prepare imports from one immutable root, then check and evaluate each module.

import cloud/beam/execute
import cloud/beam/file_system
import eyg/analysis/inference/levels_j/contextual as infer
import eyg/analysis/type_/binding/debug
import eyg/analysis/type_/isomorphic as t
import eyg/hub/cache
import eyg/interpreter/expression
import eyg/interpreter/simple_debug
import eyg/interpreter/state
import eyg/ir/dag_json
import eyg/ir/tree as ir
import eyg/parser
import gleam/bit_array
import gleam/dict
import gleam/json
import gleam/list
import gleam/result
import gleam/string
import touch_grass/file_system/read_directory

pub type Module {
  Module(source: ir.Node(execute.Meta), value: state.Value(execute.Meta))
}

pub fn paths(
  files: file_system.State,
  directory: String,
) -> Result(List(String), String) {
  use entries <- result.try(file_system.read_directory(files, directory <> "/"))
  use nested <- result.map(
    list.try_map(entries, fn(entry) {
      let #(name, kind) = entry
      let path = directory <> "/" <> name
      case kind {
        read_directory.File(_) -> Ok([path])
        read_directory.Directory -> paths(files, path)
      }
    }),
  )
  list.flatten(nested)
}

pub fn validate(files: file_system.State, runtime: execute.State) {
  use paths <- result.try(paths(files, ""))
  list.try_fold(paths, #(dict.new(), runtime), fn(acc, path) {
    let #(modules, runtime) = acc
    case is_source(path) {
      False -> Ok(acc)
      True -> {
        use source <- result.try(load(files, path, []))
        use #(value, runtime) <- result.map(prepare(source, runtime))
        #(dict.insert(modules, path, Module(source, value)), runtime)
      }
    }
  })
}

pub fn is_source(path: String) {
  string.ends_with(path, ".eyg") || string.ends_with(path, ".eyg.json")
}

pub fn load(files: file_system.State, path: String, visiting: List(String)) {
  case list.contains(visiting, path) {
    True ->
      Error(
        "Import cycle: "
        <> string.join(list.reverse([path, ..visiting]), " -> "),
      )
    False -> {
      use bytes <- result.try(file_system.read(files, path, 0, 1_073_741_824))
      case is_source(path) {
        False -> Ok(#(ir.Binary(bytes), #(0, 0)))
        True -> {
          use text <- result.try(
            bit_array.to_string(bytes)
            |> result.replace_error(path <> ": invalid UTF-8"),
          )
          use source <- result.try(
            parse(text) |> result.map_error(fn(error) { path <> ": " <> error }),
          )
          expand(source, files, path, [path, ..visiting])
        }
      }
    }
  }
}

pub fn parse(text: String) {
  case json.parse(text, dag_json.decoder(#(0, 0))) {
    Ok(source) -> Ok(source)
    Error(_) ->
      parser.all_from_string(text)
      |> result.map_error(parser.format_error(_, text))
  }
}

pub fn expand(source, files, path, visiting) {
  let #(node, meta) = source
  case node {
    ir.Reference(ir.Relative(relative)) -> {
      let directory =
        path
        |> string.split("/")
        |> list.reverse
        |> list.drop(1)
        |> list.reverse
        |> string.join("/")
      let absolute = case string.starts_with(relative, "/") {
        True -> relative
        False -> directory <> "/" <> relative
      }
      use absolute <- result.try(file_system.resolve_path(absolute))
      case string.contains(absolute, ":{") {
        True -> pattern(files, absolute, visiting)
        False -> load(files, absolute, visiting)
      }
    }
    ir.Lambda(label, body) -> {
      use body <- result.map(expand(body, files, path, visiting))
      #(ir.Lambda(label, body), meta)
    }
    ir.Apply(function, argument) -> {
      use function <- result.try(expand(function, files, path, visiting))
      use argument <- result.map(expand(argument, files, path, visiting))
      #(ir.Apply(function, argument), meta)
    }
    ir.Let(label, value, body) -> {
      use value <- result.try(expand(value, files, path, visiting))
      use body <- result.map(expand(body, files, path, visiting))
      #(ir.Let(label, value, body), meta)
    }
    _ -> Ok(source)
  }
}

fn pattern(files, pattern, visiting) {
  use #(prefix, rest) <- result.try(
    string.split_once(pattern, ":{")
    |> result.replace_error("Invalid import pattern"),
  )
  use #(_capture, suffix) <- result.try(
    string.split_once(rest, "}")
    |> result.replace_error("Invalid import pattern"),
  )
  use all <- result.try(paths(files, ""))
  let matching =
    list.filter(all, fn(path) {
      string.starts_with(path, prefix)
      && string.ends_with(path, suffix)
      && !string.contains(
        string.slice(
          path,
          string.length(prefix),
          string.length(path) - string.length(prefix) - string.length(suffix),
        ),
        "/",
      )
    })
  use items <- result.map(
    list.try_map(matching, fn(path) {
      use source <- result.map(load(files, path, visiting))
      ir.record([
        #("path", ir.string(path)),
        #(
          case is_source(path) {
            True -> "source"
            False -> "bytes"
          },
          ir.clear_annotation(source),
        ),
      ])
    }),
  )
  ir.list(items) |> ir.map_annotation(fn(_) { #(0, 0) })
}

pub fn prepare(source, runtime: execute.State) {
  let context = infer.pure() |> infer.with_effect("Abort", t.String, t.Never)
  use runtime <- result.try(check(infer.check(context, source), runtime))
  let #(value, runtime) =
    execute.pure_loop(expression.execute(source, []), runtime)
  use value <- result.map(
    result.map_error(value, fn(error) { simple_debug.describe(error.0) }),
  )
  #(value, runtime)
}

pub fn check(step, runtime: execute.State) {
  case step {
    infer.Done(analysis) ->
      case infer.all_errors(analysis) {
        [] -> Ok(runtime)
        errors ->
          Error(
            errors
            |> list.map(fn(error) { debug.render_reason(error.1) })
            |> string.join("\n"),
          )
      }
    infer.Lookup(reference, resume) -> {
      let #(value, loaded) = execute.lookup(reference, runtime)
      use _ <- result.try(value)
      let type_ =
        cache.get_reference(loaded, reference)
        |> result.map(fn(module) { module.type_ })
        |> result.replace_error(Nil)
      check(resume(type_), execute.State(..runtime, cache: loaded))
    }
  }
}
