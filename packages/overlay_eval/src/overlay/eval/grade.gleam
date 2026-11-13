//// Grade a transcript with a task's checks.
////
//// Checks read the outcome, what programs computed, the effects that reached
//// the environment and the workspace left behind. Only `Judged` checks ask a
//// model, every other check is deterministic.

import eyg/interpreter/simple_debug
import eyg/interpreter/value as v
import eyg/ir/tree as ir
import eyg/parser
import gleam/bit_array
import gleam/int
import gleam/javascript/promise.{type Promise}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import midas/continuation
import overlay/eval/evaluate
import overlay/eval/fixture/hub.{type Hub}
import overlay/eval/judge
import overlay/eval/model.{type Model}
import overlay/eval/module
import overlay/eval/task.{type Check, type Task}
import overlay/eval/transcript.{type Transcript}

pub type Verdict {
  Pass(evidence: String)
  Fail(reason: String)
  // A judge could not decide, or no judge was available.
  Unknown(reason: String)
}

pub type Graded {
  Graded(check: Check, verdict: Verdict)
}

/// Grade every check of a task, judged checks need a judge model.
pub fn task(
  task: Task,
  transcript: Transcript,
  hub: Hub,
  judge: Option(Model),
) -> Promise(List(Graded)) {
  list.fold(task.checks, promise.resolve([]), fn(done, check) {
    use done <- promise.await(done)
    use verdict <- promise.map(check_with(task, check, transcript, hub, judge))
    list.append(done, [Graded(check:, verdict:)])
  })
}

/// A trial passes when every check passes.
pub fn passed(graded: List(Graded)) -> Bool {
  list.all(graded, fn(graded) {
    case graded.verdict {
      Pass(..) -> True
      Fail(..) | Unknown(..) -> False
    }
  })
}

/// The fraction of checks that pass, partial credit for a trial.
pub fn score(graded: List(Graded)) -> Float {
  case graded {
    [] -> 1.0
    _ -> {
      let passes =
        list.count(graded, fn(graded) {
          case graded.verdict {
            Pass(..) -> True
            _ -> False
          }
        })
      int.to_float(passes) /. int.to_float(list.length(graded))
    }
  }
}

fn check_with(
  task: Task,
  check: Check,
  transcript: Transcript,
  hub: Hub,
  judge: Option(Model),
) -> Promise(Verdict) {
  case check, judge {
    task.Judged(criterion:), Some(judge) -> {
      use decision <- promise.map(judge.judge(judge, transcript, criterion))
      case decision {
        Ok(judge.Meets(reasoning)) -> Pass(reasoning)
        Ok(judge.DoesNotMeet(reasoning)) -> Fail(reasoning)
        Ok(judge.CannotTell(reasoning)) -> Unknown(reasoning)
        Error(reason) -> Unknown("the judge failed: " <> reason)
      }
    }
    task.Judged(..), None ->
      promise.resolve(Unknown("no judge was given for judged checks"))
    _, _ -> promise.resolve(deterministic(task, check, transcript, hub))
  }
}

/// Grade a check without a model, judged checks are unknown.
pub fn deterministic(
  task: Task,
  check: Check,
  transcript: Transcript,
  hub: Hub,
) -> Verdict {
  let runs =
    list.index_map(transcript.runs(transcript), fn(run, i) { #(i + 1, run) })
  case check {
    task.Computes(value: expected) ->
      case find_computed(runs, fn(value) { value == expected }) {
        Ok(index) ->
          Pass("run " <> int.to_string(index) <> " computed the value")
        Error(Nil) ->
          Fail(
            "no program computed "
            <> simple_debug.inspect(expected)
            <> computed_summary(runs),
          )
      }
    task.Satisfies(description:, predicate:) -> {
      let accepted =
        find_computed(runs, fn(value) {
          case evaluate.call(predicate, value) {
            Ok(v.Tagged("True", _)) -> True
            _ -> False
          }
        })
      case accepted {
        Ok(index) ->
          Pass(
            "run "
            <> int.to_string(index)
            <> " computed a value that "
            <> description,
          )
        Error(Nil) ->
          Fail(
            "no program computed a value that "
            <> description
            <> computed_summary(runs),
          )
      }
    }
    task.References(package:) ->
      case
        find_run(runs, fn(run) { list.contains(packages(run.code), package) })
      {
        Ok(index) ->
          Pass("run " <> int.to_string(index) <> " references @" <> package)
        Error(Nil) -> {
          let used =
            list.flat_map(runs, fn(run) { packages({ run.1 }.code) })
            |> list.unique
          Fail(
            "no program references @"
            <> package
            <> case used {
              [] -> ", no packages were referenced"
              _ -> ", referenced: @" <> string.join(used, ", @")
            },
          )
        }
      }
    task.ReadsContext(path:) ->
      case
        find_run(runs, fn(run) {
          list.any(context_paths(run.code), prefixed(_, path))
        })
      {
        Ok(index) ->
          Pass(
            "run "
            <> int.to_string(index)
            <> " reads context."
            <> string.join(path, "."),
          )
        Error(Nil) -> {
          let read =
            list.flat_map(runs, fn(run) { context_paths({ run.1 }.code) })
            |> list.map(fn(path) { "context." <> string.join(path, ".") })
            |> list.unique
          Fail(
            "no program reads context."
            <> string.join(path, ".")
            <> case read {
              [] -> ", the context was not read"
              _ -> ", read: " <> string.join(read, ", ")
            },
          )
        }
      }
    task.Fetches(url:) -> {
      let fetched =
        list.filter_map(transcript.effects, fn(effect) {
          case effect {
            transcript.Fetch(by: transcript.Program, url: fetched, status:, ..) ->
              Ok(#(fetched, status))
            _ -> Error(Nil)
          }
        })
      case
        list.find(fetched, fn(fetch) {
          string.contains(fetch.0, url)
          && case fetch.1 {
            Ok(status) -> status >= 200 && status < 300
            Error(_) -> False
          }
        })
      {
        Ok(#(fetched, _)) -> Pass("fetched " <> fetched)
        Error(Nil) ->
          Fail(
            "no successful fetch of a URL containing "
            <> url
            <> case fetched {
              [] -> ", nothing was fetched"
              _ ->
                ", fetched: "
                <> string.join(list.map(fetched, fn(f) { f.0 }), ", ")
            },
          )
      }
    }
    task.Says(text:) ->
      case find_text(transcript, text) {
        Ok(turn) ->
          Pass("said \"" <> text <> "\" in turn " <> int.to_string(turn))
        Error(Nil) -> Fail("never said \"" <> text <> "\"")
      }
    task.NeverSays(text:) ->
      case find_text(transcript, text) {
        Ok(turn) ->
          Fail("said \"" <> text <> "\" in turn " <> int.to_string(turn))
        Error(Nil) -> Pass("never said \"" <> text <> "\"")
      }
    task.FileContains(path:, text:) ->
      case transcript.workspace {
        None -> Fail("the session had no workspace")
        Some(files) ->
          case list.key_find(files, path) {
            Error(Nil) -> Fail("there is no file at " <> path)
            Ok(contents) ->
              case bit_array.to_string(contents) {
                Ok(contents) ->
                  case string.contains(contents, text) {
                    True -> Pass(path <> " contains \"" <> text <> "\"")
                    False ->
                      Fail(path <> " does not contain \"" <> text <> "\"")
                  }
                Error(Nil) -> Fail(path <> " is not text")
              }
          }
      }
    task.NoFile(path:) ->
      case transcript.workspace {
        None -> Fail("the session had no workspace")
        Some(files) ->
          case list.key_find(files, path) {
            Ok(_) -> Fail("there is a file at " <> path)
            Error(Nil) -> Pass("there is no file at " <> path)
          }
      }
    task.FileSatisfies(path:, description:, predicate:) ->
      case transcript.workspace {
        None -> Fail("the session had no workspace")
        Some(files) -> {
          let accepted = {
            use loaded <- result.try(module.load_from(files, path))
            use value <- result.try(evaluate.module(loaded, hub))
            evaluate.call(predicate, value)
          }
          case accepted {
            Ok(v.Tagged("True", _)) ->
              Pass(path <> " has a value that " <> description)
            Ok(_) -> Fail(path <> " does not have a value that " <> description)
            Error(reason) -> Fail(path <> " could not be evaluated: " <> reason)
          }
        }
      }
    task.AnyFileContains(directory:, text:) ->
      case transcript.workspace {
        None -> Fail("the session had no workspace")
        Some(files) ->
          case list.find(in_directory(files, directory), contains(_, text)) {
            Ok(#(path, _)) -> Pass(path <> " contains \"" <> text <> "\"")
            Error(Nil) ->
              Fail("no file in " <> directory <> " contains \"" <> text <> "\"")
          }
      }
    task.NoFileContains(directory:, text:) ->
      case transcript.workspace {
        None -> Fail("the session had no workspace")
        Some(files) ->
          case list.find(in_directory(files, directory), contains(_, text)) {
            Ok(#(path, _)) -> Fail(path <> " contains \"" <> text <> "\"")
            Error(Nil) ->
              Pass("no file in " <> directory <> " contains \"" <> text <> "\"")
          }
      }
    task.WorkspaceUnchanged ->
      case transcript.workspace, task.workspace {
        Some(after), Some(before) ->
          case
            after == list.sort(before, fn(a, b) { string.compare(a.0, b.0) })
          {
            True -> Pass("the workspace is unchanged")
            False -> Fail("the workspace changed: " <> changes(before, after))
          }
        _, _ -> Fail("the session had no workspace")
      }
    task.Judged(..) -> Unknown("judged checks need a model")
  }
}

fn in_directory(files: List(#(String, BitArray)), directory: String) {
  let prefix = case string.ends_with(directory, "/") {
    True -> directory
    False -> directory <> "/"
  }
  list.filter(files, fn(file) { string.starts_with(file.0, prefix) })
}

fn contains(file: #(String, BitArray), text) {
  case bit_array.to_string(file.1) {
    Ok(contents) -> string.contains(contents, text)
    Error(Nil) -> False
  }
}

fn changes(
  before: List(#(String, BitArray)),
  after: List(#(String, BitArray)),
) {
  let added =
    list.filter_map(after, fn(file) {
      case list.key_find(before, file.0) {
        Error(Nil) -> Ok("added " <> file.0)
        Ok(contents) if contents != file.1 -> Ok("changed " <> file.0)
        Ok(_) -> Error(Nil)
      }
    })
  let removed =
    list.filter_map(before, fn(file) {
      case list.key_find(after, file.0) {
        Error(Nil) -> Ok("removed " <> file.0)
        Ok(_) -> Error(Nil)
      }
    })
  string.join(list.append(added, removed), ", ")
}

fn find_computed(
  runs: List(#(Int, transcript.Run)),
  accept: fn(transcript.Value) -> Bool,
) {
  list.find_map(runs, fn(run) {
    let #(index, run) = run
    case run.outcome {
      transcript.Computed(value) ->
        case accept(value) {
          True -> Ok(index)
          False -> Error(Nil)
        }
      _ -> Error(Nil)
    }
  })
}

fn find_run(
  runs: List(#(Int, transcript.Run)),
  accept: fn(transcript.Run) -> Bool,
) {
  list.find_map(runs, fn(run) {
    let #(index, run) = run
    case accept(run) {
      True -> Ok(index)
      False -> Error(Nil)
    }
  })
}

fn computed_summary(runs: List(#(Int, transcript.Run))) {
  let values =
    list.filter_map(runs, fn(run) {
      case { run.1 }.outcome {
        transcript.Computed(value) -> Ok(simple_debug.inspect(value))
        _ -> Error(Nil)
      }
    })
  case list.reverse(values) {
    [] -> ", no program computed a value"
    [last, ..] -> ", the last value computed was " <> cut(last)
  }
}

fn find_text(transcript: Transcript, text) {
  let text = string.lowercase(text)
  list.index_map(transcript.turns, fn(turn, index) { #(index + 1, turn) })
  |> list.find_map(fn(turn) {
    let #(index, turn) = turn
    case
      list.any(turn.steps, fn(step) {
        string.contains(string.lowercase(step.text), text)
      })
    {
      True -> Ok(index)
      False -> Error(Nil)
    }
  })
}

/// The packages a program references, by name.
pub fn packages(code: String) -> List(String) {
  case parser.all_from_string(code) {
    Ok(source) ->
      ir.list_references(source)
      |> list.filter_map(fn(reference) {
        case reference {
          ir.Package(package:) -> Ok(package)
          ir.Version(package:, ..) -> Ok(package)
          ir.Pinned(release: ir.Release(package:, ..)) -> Ok(package)
          ir.Content(..) | ir.Relative(..) -> Error(Nil)
        }
      })
      |> list.unique
    Error(_) -> []
  }
}

/// The field paths of the context a program reads, `context.a.b` is `["a", "b"]`.
pub fn context_paths(code: String) -> List(List(String)) {
  case parser.all_from_string(code) {
    Ok(source) ->
      {
        use paths, node <- ir.fold(source, [])
        case node {
          #(ir.Apply(#(ir.Select(label), _), argument), _) ->
            case context_path(argument) {
              Ok(path) -> [list.append(path, [label]), ..paths]
              Error(Nil) -> paths
            }
          _ -> paths
        }
        |> continuation.return
      }(list.reverse)
      |> list.unique
      |> keep_longest
    Error(_) -> []
  }
}

fn context_path(node) {
  case node {
    #(ir.Variable("context"), _) -> Ok([])
    #(ir.Apply(#(ir.Select(label), _), argument), _) ->
      result.map(context_path(argument), list.append(_, [label]))
    _ -> Error(Nil)
  }
}

/// A path read inside a longer one is not a separate read.
fn keep_longest(paths: List(List(String))) {
  list.filter(paths, fn(path) {
    !list.any(paths, fn(other) { other != path && prefixed(other, path) })
  })
}

fn prefixed(path, prefix) {
  case path, prefix {
    _, [] -> True
    [a, ..path], [b, ..prefix] if a == b -> prefixed(path, prefix)
    _, _ -> False
  }
}

fn cut(text) {
  case string.length(text) > 200 {
    True -> string.slice(text, 0, 200) <> "…"
    False -> text
  }
}
