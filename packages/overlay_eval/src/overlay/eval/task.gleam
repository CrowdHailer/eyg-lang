//// A task is one case of an eval: prompts for the agent, what the session
//// starts with, the checks that grade the transcript and a reference solution.
////
//// Tasks are written as EYG records, see `decode`, so expected values are
//// ordinary EYG values and checks can be EYG functions.

import eyg/interpreter/break
import eyg/interpreter/cast
import eyg/interpreter/simple_debug
import eyg/interpreter/state as istate
import eyg/interpreter/value as v
import gleam/bit_array
import gleam/dict
import gleam/http
import gleam/http/request
import gleam/http/response
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import overlay/eval/agent
import overlay/eval/environment
import overlay/web/tools

pub type Value =
  istate.Value(tools.Meta)

pub type Task {
  Task(
    name: String,
    description: String,
    tags: List(String),
    prompts: List(String),
    // Files of the workspace, sessions without one cannot use file effects.
    workspace: Option(List(#(String, BitArray))),
    routes: List(environment.Route),
    checks: List(Check),
    // Replies for each turn that solve the task, followed by the oracle agent.
    reference: List(List(agent.Reply)),
    max_model_calls: Int,
  )
}

pub type Check {
  // A program computed this value.
  Computes(value: Value)
  // A program computed a value this EYG function returns True for.
  Satisfies(description: String, predicate: Value)
  // A program referenced a package, by name, version or pinned release.
  References(package: String)
  // A program read this field path of its context, `context.a.b`.
  ReadsContext(path: List(String))
  // A program fetched a URL containing this text and got a successful response.
  Fetches(url: String)
  // The agent's replies contain this text, ignoring case.
  Says(text: String)
  // None of the agent's replies contain this text, ignoring case.
  NeverSays(text: String)
  // The workspace ends with a file at this path containing this text.
  FileContains(path: String, text: String)
  // The workspace ends without a file at this path.
  NoFile(path: String)
  // A file of the workspace is a module with a value this EYG function returns
  // True for.
  FileSatisfies(path: String, description: String, predicate: Value)
  // A file in this directory of the workspace contains this text.
  AnyFileContains(directory: String, text: String)
  // No file in this directory of the workspace contains this text.
  NoFileContains(directory: String, text: String)
  // The workspace ends exactly as it started.
  WorkspaceUnchanged
  // A model judges that the transcript meets the criterion.
  Judged(criterion: String)
}

pub const default_max_model_calls = 20

/// Describe a check in a sentence, for reports.
pub fn describe(check: Check) -> String {
  case check {
    Computes(value:) -> "computes " <> simple_debug.inspect(value)
    Satisfies(description:, ..) -> "computes a value that " <> description
    References(package:) -> "references @" <> package
    ReadsContext(path:) -> "reads context." <> string.join(path, ".")
    Fetches(url:) -> "fetches " <> url
    Says(text:) -> "says \"" <> text <> "\""
    NeverSays(text:) -> "never says \"" <> text <> "\""
    FileContains(path:, text:) ->
      "leaves " <> path <> " containing \"" <> text <> "\""
    NoFile(path:) -> "leaves no file at " <> path
    FileSatisfies(path:, description:, ..) ->
      "leaves " <> path <> " with a value that " <> description
    AnyFileContains(directory:, text:) ->
      "leaves a file in " <> directory <> " containing \"" <> text <> "\""
    NoFileContains(directory:, text:) ->
      "leaves no file in " <> directory <> " containing \"" <> text <> "\""
    WorkspaceUnchanged -> "leaves the workspace unchanged"
    Judged(criterion:) -> "judged: " <> criterion
  }
}

/// Decode a task from an EYG record.
///
/// ```eyg
/// {
///   description: "Add two numbers",
///   tags: ["arithmetic"],
///   prompts: ["What is 2 + 3?"],
///   checks: [Computes(5), Says("5")],
///   reference: [[Run("!int_add(2, 3)"), Say("It is 5.")]],
/// }
/// ```
///
/// `tags`, `workspace`, `routes`, `reference` and `max_model_calls` are optional.
/// A workspace is a list of `{path, contents}` and routes are
/// `{url, status, body}` answered to GET requests.
pub fn decode(name: String, value: Value) -> Result(Task, String) {
  let context = fn(result: Result(a, istate.Reason(tools.Meta)), field) {
    result.map_error(result, fn(reason) {
      name <> "." <> field <> ": " <> simple_debug.describe(reason)
    })
  }
  use fields <- result.try(context(cast.as_record(value), "task"))
  use description <- result.try(context(
    cast.field("description", cast.as_string, value),
    "description",
  ))
  use tags <- result.try(case dict.has_key(fields, "tags") {
    True -> context(cast.field("tags", strings, value), "tags")
    False -> Ok([])
  })
  use prompts <- result.try(context(
    cast.field("prompts", strings, value),
    "prompts",
  ))
  use workspace <- result.try(case dict.has_key(fields, "workspace") {
    True ->
      context(cast.field("workspace", workspace, value), "workspace")
      |> result.map(Some)
    False -> Ok(None)
  })
  use routes <- result.try(case dict.has_key(fields, "routes") {
    True -> context(cast.field("routes", routes, value), "routes")
    False -> Ok([])
  })
  use checks <- result.try(context(
    cast.field("checks", cast.as_list_of(_, check), value),
    "checks",
  ))
  use reference <- result.try(case dict.has_key(fields, "reference") {
    True ->
      context(
        cast.field("reference", cast.as_list_of(_, turn_reference), value),
        "reference",
      )
    False -> Ok([])
  })
  use max_model_calls <- result.try(
    case dict.has_key(fields, "max_model_calls") {
      True ->
        context(
          cast.field("max_model_calls", cast.as_integer, value),
          "max_model_calls",
        )
      False -> Ok(default_max_model_calls)
    },
  )
  case prompts, checks, max_model_calls > 0 {
    [], _, _ -> Error(name <> ".prompts: a task needs at least one prompt")
    _, [], _ -> Error(name <> ".checks: a task needs at least one check")
    _, _, False -> Error(name <> ".max_model_calls: must be positive")
    _, _, True ->
      Ok(Task(
        name:,
        description:,
        tags:,
        prompts:,
        workspace:,
        routes:,
        checks:,
        reference:,
        max_model_calls:,
      ))
  }
}

fn strings(value) {
  cast.as_list_of(value, cast.as_string)
}

fn workspace(value) {
  cast.as_list_of(value, fn(file) {
    use path <- result.try(cast.field("path", cast.as_string, file))
    use contents <- result.try(cast.field("contents", cast.as_string, file))
    Ok(#(path, bit_array.from_string(contents)))
  })
}

fn routes(value) {
  cast.as_list_of(value, fn(route) {
    use url <- result.try(cast.field("url", cast.as_string, route))
    use status <- result.try(cast.field("status", cast.as_integer, route))
    use body <- result.try(cast.field("body", cast.as_string, route))
    let response =
      response.new(status) |> response.set_body(bit_array.from_string(body))
    case request.to(url) {
      Ok(request) ->
        Ok(environment.Route(http.Get, request.host, request.path, response))
      Error(Nil) -> Error(break.IncorrectTerm("a URL", v.String(url)))
    }
  })
}

fn check(value) {
  cast.as_variant(value, [
    #("Computes", fn(value) { Ok(Computes(value)) }),
    #("Satisfies", fn(value) {
      use description <- result.try(cast.field(
        "description",
        cast.as_string,
        value,
      ))
      use predicate <- result.try(cast.field("check", Ok, value))
      Ok(Satisfies(description:, predicate:))
    }),
    #("References", fn(value) { result.map(cast.as_string(value), References) }),
    #("ReadsContext", fn(value) { result.map(strings(value), ReadsContext) }),
    #("Fetches", fn(value) { result.map(cast.as_string(value), Fetches) }),
    #("Says", fn(value) { result.map(cast.as_string(value), Says) }),
    #("NeverSays", fn(value) { result.map(cast.as_string(value), NeverSays) }),
    #("FileContains", fn(value) {
      use path <- result.try(cast.field("path", cast.as_string, value))
      use text <- result.try(cast.field("text", cast.as_string, value))
      Ok(FileContains(path:, text:))
    }),
    #("NoFile", fn(value) { result.map(cast.as_string(value), NoFile) }),
    #("FileSatisfies", fn(value) {
      use path <- result.try(cast.field("path", cast.as_string, value))
      use description <- result.try(cast.field(
        "description",
        cast.as_string,
        value,
      ))
      use predicate <- result.try(cast.field("check", Ok, value))
      Ok(FileSatisfies(path:, description:, predicate:))
    }),
    #("AnyFileContains", fn(value) {
      use directory <- result.try(cast.field("directory", cast.as_string, value))
      use text <- result.try(cast.field("text", cast.as_string, value))
      Ok(AnyFileContains(directory:, text:))
    }),
    #("NoFileContains", fn(value) {
      use directory <- result.try(cast.field("directory", cast.as_string, value))
      use text <- result.try(cast.field("text", cast.as_string, value))
      Ok(NoFileContains(directory:, text:))
    }),
    #("WorkspaceUnchanged", fn(_) { Ok(WorkspaceUnchanged) }),
    #("Judged", fn(value) { result.map(cast.as_string(value), Judged) }),
  ])
}

/// A turn of a reference solution: programs run with `Run` and an answer
/// given with `Say`, each step is a reply of its own.
fn turn_reference(value) {
  cast.as_list_of(value, fn(step) {
    cast.as_variant(step, [
      #("Run", fn(code) {
        result.map(cast.as_string(code), fn(code) { agent.Reply("", [code]) })
      }),
      #("Say", fn(text) {
        result.map(cast.as_string(text), fn(text) { agent.Reply(text, []) })
      }),
    ])
  })
}

/// Every tag used by a list of tasks, in order of first use.
pub fn tags(tasks: List(Task)) -> List(String) {
  list.flat_map(tasks, fn(task) { task.tags }) |> list.unique
}
