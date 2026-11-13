//// Run evals of Overlay agents and contexts.
////
//// ```sh
//// gleam run -m overlay/eval -- run <suite.eyg> [options]
//// gleam run -m overlay/eval -- validate <suite.eyg> [options]
//// gleam run -m overlay/eval -- compare <run.json> <run.json>
//// gleam run -m overlay/eval -- calibrate <run.json> [labels.json]
//// ```
////
//// See the README for options.

import argv
import envoy
import filepath
import gleam/dict
import gleam/int
import gleam/io
import gleam/javascript/promise.{type Promise}
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import gleam/time/calendar
import gleam/time/timestamp
import javascript/mutable_reference
import overlay/eval/agent
import overlay/eval/calibration
import overlay/eval/cassette
import overlay/eval/environment.{type Environment}
import overlay/eval/fixture/hub
import overlay/eval/fixture/repository
import overlay/eval/fixture/site
import overlay/eval/grade
import overlay/eval/model.{type Model}
import overlay/eval/module
import overlay/eval/options.{type Options}
import overlay/eval/process
import overlay/eval/pure
import overlay/eval/report
import overlay/eval/run
import overlay/eval/session
import overlay/eval/stats
import overlay/eval/suite.{type Suite}
import overlay/eval/summary
import overlay/eval/task.{type Task}
import overlay/eval/trial.{type Trial}
import simplifile

pub fn main() -> Promise(Nil) {
  case argv.load().arguments {
    ["run", suite, ..rest] ->
      with_options(rest, fn(options) { run(suite, options) })
    ["validate", suite, ..rest] ->
      with_options(rest, fn(options) { validate(suite, options) })
    ["compare", first, second] -> promise.resolve(compare(first, second))
    ["calibrate", run] -> promise.resolve(labels(run))
    ["calibrate", run, labels] -> promise.resolve(calibrate(run, labels))
    [] | ["--help"] -> {
      io.println(usage)
      promise.resolve(Nil)
    }
    _ -> promise.resolve(process.fail(usage))
  }
}

const usage =
  "Run evals of Overlay agents and contexts.

  gleam run -m overlay/eval -- run <suite.eyg> [options]
  gleam run -m overlay/eval -- validate <suite.eyg> [options]
  gleam run -m overlay/eval -- compare <run.json> <run.json>
  gleam run -m overlay/eval -- calibrate <run.json> [labels.json]

Options:
  --context <path>   an EYG module to use as the context, repeat to compare
                     contexts, `none` is Overlay's default context
  --model <model>    scripted:oracle, scripted:null, ollama:<name> (Ollama
                     Cloud, OLLAMA_API_KEY), ollama-local:<name> or
                     mistral:<name> (MISTRAL_API_KEY), or openai-local:<name>
                     (OVERLAY_EVAL_OPENAI_ORIGIN, default http://127.0.0.1:7210)
  --judge <model>    the model for judged checks, as --model
  --trials <n>       trials of each task, default 1
  --timeout <n>      seconds a model has to answer a request, default 300,
                     0 waits for as long as it takes
  --tag <tag>        only run tasks with the tag, repeat for more tags
  --root <path>      the repository with eyg_packages and guides, default ../..
  --out <path>       where reports are written, default evals
  --record <path>    record model exchanges into cassettes
  --replay <path>    answer from recorded cassettes instead of models
  --lenient          replay cassettes even when requests have changed"

fn with_options(args, then) {
  case options.parse(args, options.default_options()) {
    Ok(options) -> then(options)
    Error(reason) -> {
      process.fail(reason <> "\n\n" <> usage)
      promise.resolve(Nil)
    }
  }
}

/// Resolve a model from its description, keys are read from the environment.
pub fn model(description: String) -> Result(Model, String) {
  case string.split_once(description, ":") {
    Ok(#("scripted", "null")) -> Ok(model.Scripted(agent.null()))
    Ok(#("ollama", name)) ->
      envoy.get("OLLAMA_API_KEY")
      |> result.replace_error("OLLAMA_API_KEY is needed for Ollama Cloud")
      |> result.map(model.ollama_cloud(name, _))
    Ok(#("ollama-local", name)) -> Ok(model.ollama_local(name))
    Ok(#("openai-local", _)) ->
      pure.configuration(description)
      |> result.map(fn(llm) { model.Provider(llm, model.network()) })
    Ok(#("mistral", name)) ->
      envoy.get("MISTRAL_API_KEY")
      |> result.replace_error("MISTRAL_API_KEY is needed for Mistral")
      |> result.map(model.mistral(name, _))
    Error(_) if description == "" ->
      Error(
        "run requires --model; use validate for offline reference solutions",
      )
    _ -> Error("unknown model " <> description)
  }
}

/// The environment of every session: the repository's packages on a hub,
/// its guides on the site and its source as a GitHub repository.
pub fn environment(root: String) -> Result(Environment, String) {
  use hub <- result.try(hub.publish_directory(
    hub.new(),
    filepath.join(root, "eyg_packages"),
  ))
  use site <- result.try(site.load(filepath.join(root, "guides")))
  use repository <- result.map(repository.load(
    "CrowdHailer",
    "eyg-lang",
    "main",
    root,
  ))
  environment.Environment(..environment.empty(), hub:, site:, repositories: [
    repository,
  ])
}

fn context(
  environment: Environment,
  path: String,
) -> Result(#(session.Context, String), String) {
  case path {
    "none" -> Ok(#(session.NoContext, "none"))
    _ -> {
      // Contexts are shared with their packages pinned, as `eyg share` does.
      let resolve = hub.resolve(environment.hub)
      use loaded <- result.map(module.load_pinned(path, resolve))
      #(session.Module(loaded), path)
    }
  }
}

fn prepare(suite_path: String, options: Options) {
  use environment <- result.try(environment(options.root))
  use suite <- result.try(suite.load(suite_path, environment.hub))
  let suite = suite.tagged(suite, list.reverse(options.tags))
  use _ <- result.try(case suite.tasks {
    [] -> Error("the suite has no selected tasks")
    _ -> Ok(Nil)
  })
  use contexts <- result.map(
    list.try_map(options.contexts, context(environment, _)),
  )
  #(environment, suite, contexts)
}

fn run(suite_path: String, options: Options) -> Promise(Nil) {
  case
    prepare(suite_path, options),
    model_or_scripted(options.model, options.replay != None)
  {
    Error(reason), _ | _, Error(reason) -> {
      process.fail(reason)
      promise.resolve(Nil)
    }
    Ok(#(environment, suite, contexts)), Ok(base) -> {
      let judge = case options.judge {
        Some(description) ->
          case options.replay {
            Some(_) -> model_for_replay(description) |> result.map(Some)
            None -> model(description) |> result.map(Some)
          }
        None -> Ok(None)
      }
      case judge {
        Error(reason) -> {
          process.fail(reason)
          promise.resolve(Nil)
        }
        Ok(judge) -> {
          let stamp =
            timestamp.system_time()
            |> timestamp.to_rfc3339(calendar.utc_offset)
            |> string.slice(0, 19)
            |> string.replace(":", "-")
          use logs <- promise.map(
            list.fold(contexts, promise.resolve([]), fn(done, context) {
              use done <- promise.await(done)
              let #(context, name) = context
              use log <- promise.map(run_context(
                environment,
                suite,
                context,
                name,
                base,
                judge,
                options,
                stamp,
              ))
              [log, ..done]
            }),
          )
          case list.reverse(logs) {
            [first, ..others] ->
              list.each(others, fn(other) {
                let path =
                  filepath.join(
                    filepath.join(options.out, suite.name),
                    stamp <> "-comparison-" <> slug(other.0.context) <> ".md",
                  )
                write(path, report.comparison(first, other))
                io.println("Comparison: " <> path)
              })
            [] -> Nil
          }
        }
      }
    }
  }
}

pub fn model_for_replay(description) {
  case string.split_once(description, ":") {
    Ok(#("ollama", name)) -> Ok(model.ollama_cloud(name, "cassette"))
    Ok(#("mistral", name)) -> Ok(model.mistral(name, "cassette"))
    _ -> model(description)
  }
}

fn model_or_scripted(description, replay) {
  case description {
    // The oracle depends on the task, it is chosen for each trial.
    "scripted:oracle" -> Ok(model.Scripted(agent.null()))
    _ ->
      case replay {
        True -> model_for_replay(description)
        False -> model(description)
      }
  }
}

fn run_context(
  environment,
  suite: Suite,
  context,
  name,
  base: Model,
  judge: Option(Model),
  options: Options,
  stamp,
) {
  let recorders = mutable_reference.new(dict.new())
  let model_for = fn(task: Task, number) {
    let model = case options.model {
      "scripted:oracle" -> trial.oracle(task)
      _ -> base
    }
    exchange(
      model,
      options,
      recorders,
      cassette_path(options, name, task, number, "model"),
    )
  }
  let judge_for = fn(task: Task, number) {
    option.map(judge, exchange(
      _,
      options,
      recorders,
      cassette_path(options, name, task, number, "judge"),
    ))
  }
  let config =
    run.Config(
      suite:,
      environment:,
      context:,
      context_name: name,
      model: case options.model {
        "scripted:oracle" -> model.Scripted(agent.scripted([]))
        _ -> base
      },
      judge:,
      trials: options.trials,
      model_for:,
      judge_for:,
    )
  io.println("Running " <> suite.name <> " with context " <> name)
  use result <- promise.map(run.run(config, fn(trial) { progress(trial) }))
  // Cassettes are written once every trial has finished.
  dict.each(mutable_reference.get(recorders), fn(path, recorder) {
    write(path, json.to_string(cassette.encode(cassette.recorded(recorder))))
  })
  let result = case options.model {
    "scripted:oracle" -> run.Run(..result, model: "scripted:oracle")
    _ -> result
  }
  let directory =
    filepath.join(
      filepath.join(options.out, suite.name),
      stamp <> "-" <> slug(name) <> "-" <> slug(result.model),
    )
  write(
    filepath.join(directory, "run.json"),
    json.to_string(report.log(result)),
  )
  let header = report.header(result)
  let summary = summary.summarise(result)
  write(
    filepath.join(directory, "summary.md"),
    report.markdown(header, summary),
  )
  list.each(result.trials, fn(trial) {
    let assert Ok(task) =
      list.find(suite.tasks, fn(task) { task.name == trial.task })
    write(
      filepath.join(
        filepath.join(directory, "trials"),
        trial.task <> "-" <> int.to_string(trial.number) <> ".md",
      ),
      report.trial(task, trial),
    )
  })
  io.println(
    "Pass rate "
    <> stats.percent(summary.rate.mean)
    <> " over "
    <> int.to_string(summary.rate.samples)
    <> " tasks, report in "
    <> directory,
  )
  #(header, summary)
}

fn exchange(model: Model, options: Options, recorders, path) -> Model {
  // A provider that stalls would otherwise hold the run open indefinitely.
  let model = case model, options.timeout {
    model.Provider(llm:, transport:), seconds if seconds > 0 ->
      model.Provider(llm:, transport: model.with_timeout(transport, seconds))
    _, _ -> model
  }
  case model, options.record, options.replay {
    model.Provider(llm:, transport:), Some(_), _ -> {
      let recorder = cassette.recorder()
      let _ =
        mutable_reference.set(
          recorders,
          dict.insert(mutable_reference.get(recorders), path, recorder),
        )
      model.Provider(llm:, transport: cassette.record(transport, recorder))
    }
    model.Provider(llm:, ..), None, Some(_) -> {
      let matching = case options.lenient {
        True -> cassette.Lenient
        False -> cassette.Strict
      }
      let recorded =
        simplifile.read(path)
        |> result.replace_error(Nil)
        |> result.try(fn(text) {
          json.parse(text, cassette.decoder()) |> result.replace_error(Nil)
        })
        |> result.unwrap(cassette.Cassette([]))
      model.Provider(llm:, transport: cassette.replay(recorded, matching))
    }
    _, _, _ -> model
  }
}

fn cassette_path(options: Options, context, task: Task, number, kind) {
  let directory = option.or(options.record, options.replay) |> option.unwrap("")
  filepath.join(
    filepath.join(directory, slug(context)),
    task.name <> "-" <> int.to_string(number) <> "." <> kind <> ".json",
  )
}

fn progress(trial: Trial) {
  let mark = case trial.passed {
    True -> "pass"
    False -> {
      process.exit_code(1)
      "FAIL"
    }
  }
  let failing =
    list.find_map(trial.graded, fn(graded) {
      case graded.verdict {
        grade.Pass(..) -> Error(Nil)
        grade.Fail(reason) | grade.Unknown(reason) ->
          Ok(task.describe(graded.check) <> ": " <> first_line(reason))
      }
    })
  io.println(
    mark
    <> " "
    <> trial.task
    <> " #"
    <> int.to_string(trial.number)
    <> " ("
    <> int.to_string(trial.transcript.model_calls)
    <> " model calls)"
    <> case failing {
      Ok(reason) -> " " <> reason
      Error(Nil) -> ""
    },
  )
}

/// Check every task: its reference solution must pass every deterministic
/// check, and an agent that does nothing must fail one.
fn validate(suite_path: String, options: Options) -> Promise(Nil) {
  case prepare(suite_path, options) {
    Error(reason) -> {
      process.fail(reason)
      promise.resolve(Nil)
    }
    Ok(#(environment, suite, contexts)) -> {
      use problems <- promise.map(validate_contexts(
        environment,
        suite,
        contexts,
      ))
      case problems {
        [] ->
          io.println(
            "Every task of "
            <> suite.name
            <> " is solved by its reference and failed by the null agent in "
            <> int.to_string(list.length(contexts))
            <> " contexts.",
          )
        _ -> {
          list.each(problems, io.println)
          process.exit_code(1)
        }
      }
    }
  }
}

/// Validate every selected context, keeping its name on each diagnostic.
pub fn validate_contexts(
  environment: Environment,
  suite: Suite,
  contexts: List(#(session.Context, String)),
) -> Promise(List(String)) {
  list.fold(contexts, promise.resolve([]), fn(done, selected) {
    use done <- promise.await(done)
    let #(context, name) = selected
    list.fold(suite.tasks, promise.resolve(done), fn(done, task) {
      use done <- promise.await(done)
      use problems <- promise.map(validate_task(environment, context, task))
      list.append(
        done,
        list.map(problems, fn(problem) { name <> ": " <> problem }),
      )
    })
  })
}

pub fn validate_task(
  environment: Environment,
  context: session.Context,
  task: Task,
) -> Promise(List(String)) {
  let deterministic =
    list.filter(task.checks, fn(check) {
      case check {
        task.Judged(..) -> False
        _ -> True
      }
    })
  let only = task.Task(..task, checks: deterministic)
  use oracle <- promise.await(trial.run(
    environment,
    context,
    trial.oracle(only),
    None,
    only,
    1,
  ))
  use null <- promise.map(trial.run(
    environment,
    context,
    model.Scripted(agent.null()),
    None,
    only,
    1,
  ))
  let reference = case task.reference {
    [] -> [task.name <> ": has no reference solution"]
    _ ->
      list.filter_map(oracle.graded, fn(graded) {
        case graded.verdict {
          grade.Pass(..) -> Error(Nil)
          grade.Fail(reason) | grade.Unknown(reason) ->
            Ok(
              task.name
              <> ": the reference fails "
              <> task.describe(graded.check)
              <> ": "
              <> first_line(reason),
            )
        }
      })
  }
  let shortcut = case deterministic, null.passed {
    [], _ -> [task.name <> ": has only judged checks, it cannot be validated"]
    _, True -> [task.name <> ": an agent that does nothing passes"]
    _, False -> []
  }
  list.append(reference, shortcut)
}

fn compare(first: String, second: String) -> Nil {
  let read = read_log(_, report.log_decoder())
  case read(first), read(second) {
    Ok(first), Ok(second) -> io.println(report.comparison(first, second))
    Error(reason), _ | _, Error(reason) -> process.fail(reason)
  }
}

/// Write out every judged check of a run for a person to grade.
///
/// The judge's own verdicts are left out on purpose: seeing them first is how
/// a labeller ends up agreeing with the instrument they are calibrating.
fn labels(path: String) -> Nil {
  case read_log(path, report.judged_decoder()) {
    Error(reason) -> process.fail(reason)
    Ok([]) -> process.fail(path <> " has no judged checks")
    Ok(judged) -> {
      let lines =
        list.map(judged, fn(judged: report.Judged) {
          "  "
          <> json.to_string(
            json.object([
              #("task", json.string(judged.task)),
              #("trial", json.int(judged.trial)),
              #("criterion", json.string(judged.criterion)),
              #("verdict", json.string("")),
            ]),
          )
        })
      io.println("[\n" <> string.join(lines, ",\n") <> "\n]")
      io.println_error(
        int.to_string(list.length(judged))
        <> " judged checks. Read the trial reports beside the run log, write"
        <> " pass or fail as each verdict, then compare with:\n\n  gleam run"
        <> " -m overlay/eval -- calibrate "
        <> path
        <> " <labels.json>",
      )
    }
  }
}

/// Compare a judge with a person.
fn calibrate(path: String, labels: String) -> Nil {
  case
    read_log(path, report.judged_decoder()),
    read_log(labels, calibration.labels_decoder())
  {
    Ok(judged), Ok(labels) ->
      io.println(calibration.markdown(calibration.compare(judged, labels)))
    Error(reason), _ | _, Error(reason) -> process.fail(reason)
  }
}

fn read_log(path, decoder) {
  simplifile.read(path)
  |> result.map_error(simplifile.describe_error)
  |> result.try(fn(text) {
    json.parse(text, decoder)
    |> result.replace_error(
      path <> " is not a run log, or a labels file of pass and fail verdicts",
    )
  })
}

fn write(path: String, contents: String) -> Nil {
  let _ = simplifile.create_directory_all(filepath.directory_name(path))
  case simplifile.write(path, contents) {
    Ok(Nil) -> Nil
    Error(reason) ->
      process.fail(
        "unable to write " <> path <> ": " <> simplifile.describe_error(reason),
      )
  }
}

fn slug(text: String) -> String {
  string.to_graphemes(text)
  |> list.map(fn(character) {
    case
      string.contains(
        "abcdefghijklmnopqrstuvwxyz0123456789-.",
        string.lowercase(character),
      )
    {
      True -> string.lowercase(character)
      False -> "_"
    }
  })
  |> string.concat
}

fn first_line(text) {
  case string.split_once(text, "\n") {
    Ok(#(line, _)) -> line
    Error(Nil) -> text
  }
}
