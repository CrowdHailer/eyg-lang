//// The configuration of a cloud, written in EYG in `cloud.eyg`.
////
//// `cloud.eyg` evaluates to a record:
////
//// - `workspaces` a list of `{name, file}`, each file is a workspace's `workspace.eyg`,
////   relative to `cloud.eyg`.
//// - `shells` optional, a record of named shell policies people choose from in the web shell.
////   The first person to sign in is the admin, their shell has every effect.
////
//// Like workspace configuration it is evaluated by each process that needs its policies,
//// see `notes/cloud-process-boundaries.md`.

import cloud/beam/execute
import cloud/check
import eyg/interpreter/cast
import eyg/interpreter/simple_debug
import eyg/interpreter/value as v
import filepath
import gleam/dict
import gleam/list
import gleam/option.{None, Some}
import gleam/result
import gleam/string
import simplifile

pub type Entry {
  Entry(name: String, file: String)
}

pub type Instance {
  Instance(
    workspaces: List(Entry),
    shells: List(#(String, execute.Policy)),
    state: execute.State,
  )
}

pub type Loader =
  fn() -> Result(Instance, String)

pub fn loader(file: String, state: execute.State) -> Loader {
  fn() { load(file, state) }
}

pub fn load(file: String, state: execute.State) -> Result(Instance, String) {
  use code <- result.try(
    simplifile.read(file)
    |> result.map_error(fn(reason) {
      "Failed to read " <> file <> ": " <> simplifile.describe_error(reason)
    }),
  )
  let directory = filepath.directory_name(file)
  let state = execute.State(..state, root: Some(directory))
  use #(source, _, state, _) <- result.try(execute.prepare_configuration(
    code,
    state,
    check_shells,
  ))
  let host = execute.configuration_host(fn(_) { Error("no secrets") })
  let #(execute.Run(result:, ..), state) =
    execute.run_configuration_source(
      source,
      execute.configuration(),
      host,
      state,
    )
  case result {
    Ok(Some(value)) -> decode(value, directory, state)
    Ok(None) -> Error(file <> " has no value")
    Error(reason) -> Error(file <> ": " <> reason)
  }
}

fn check_shells(type_) {
  case check.field(type_, "shells") {
    Error(_) -> Ok(Nil)
    Ok(shells) -> {
      use fields <- result.try(check.fields(shells))
      list.try_each(fields, fn(field) {
        execute.check_shell(field.1)
        |> result.map_error(fn(reason) {
          "shells." <> field.0 <> ": " <> reason
        })
      })
    }
  }
}

/// A cloud of one workspace, used when there is no `cloud.eyg`.
pub fn single(name: String, file: String, state: execute.State) -> Instance {
  Instance(workspaces: [Entry(name, file)], shells: [], state:)
}

fn decode(value, directory, state) {
  let entry = fn(value) {
    use name <- result.try(cast.field("name", cast.as_string, value))
    use file <- result.map(cast.field("file", cast.as_string, value))
    let file = case file {
      "./" <> file -> file
      file -> file
    }
    Entry(name, filepath.join(directory, file))
  }
  use workspaces <- result.try(
    cast.field("workspaces", cast.as_list_of(_, entry), value)
    |> result.map_error(fn(reason) {
      "workspaces: " <> simple_debug.describe(reason)
    }),
  )
  use shells <- result.map(case cast.field("shells", Ok, value) {
    Ok(v.Record(fields)) ->
      dict.to_list(fields)
      |> list.sort(fn(a, b) { string.compare(a.0, b.0) })
      |> list.try_map(fn(field) {
        let #(name, policy) = field
        execute.decode_policy(policy, state)
        |> result.map(fn(policy) { #(name, policy) })
        |> result.map_error(fn(reason) { "shells." <> name <> ": " <> reason })
      })
    Ok(_) -> Error("shells must be a record of policies")
    Error(_) -> Ok([])
  })
  Instance(workspaces:, shells:, state:)
}
