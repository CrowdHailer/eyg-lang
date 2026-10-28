//// Configuration of eval commands.

import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}

pub type Options {
  Options(
    contexts: List(String),
    model: String,
    judge: Option(String),
    trials: Int,
    // Seconds a model has to answer a request, 0 for as long as it takes.
    timeout: Int,
    tags: List(String),
    root: String,
    out: String,
    record: Option(String),
    replay: Option(String),
    lenient: Bool,
  )
}

pub fn default_options() -> Options {
  Options(
    contexts: [],
    model: "",
    judge: None,
    trials: 1,
    timeout: 300,
    tags: [],
    root: "../..",
    out: "evals",
    record: None,
    replay: None,
    lenient: False,
  )
}

/// Parse command line options.
pub fn parse(args: List(String), options: Options) -> Result(Options, String) {
  case args {
    [] if options.record != None && options.replay != None ->
      Error("--record and --replay cannot be used together")
    [] if options.lenient && options.replay == None ->
      Error("--lenient requires --replay")
    [] ->
      case options.contexts {
        [] -> Ok(Options(..options, contexts: ["none"]))
        contexts -> Ok(Options(..options, contexts: list.reverse(contexts)))
      }
    ["--context", context, ..rest] ->
      parse(rest, Options(..options, contexts: [context, ..options.contexts]))
    ["--model", model, ..rest] -> parse(rest, Options(..options, model:))
    ["--judge", judge, ..rest] ->
      parse(rest, Options(..options, judge: Some(judge)))
    ["--trials", trials, ..rest] ->
      case int.parse(trials) {
        Ok(trials) if trials > 0 -> parse(rest, Options(..options, trials:))
        _ -> Error("--trials needs a positive number, not " <> trials)
      }
    ["--timeout", timeout, ..rest] ->
      case int.parse(timeout) {
        Ok(timeout) if timeout >= 0 -> parse(rest, Options(..options, timeout:))
        _ -> Error("--timeout needs seconds, or 0 to wait, not " <> timeout)
      }
    ["--tag", tag, ..rest] ->
      parse(rest, Options(..options, tags: [tag, ..options.tags]))
    ["--root", root, ..rest] -> parse(rest, Options(..options, root:))
    ["--out", out, ..rest] -> parse(rest, Options(..options, out:))
    ["--record", path, ..rest] ->
      parse(rest, Options(..options, record: Some(path)))
    ["--replay", path, ..rest] ->
      parse(rest, Options(..options, replay: Some(path)))
    ["--lenient", ..rest] -> parse(rest, Options(..options, lenient: True))
    [unknown, ..] -> Error("unknown option " <> unknown)
  }
}
