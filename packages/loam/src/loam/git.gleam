//// Trusted Git acquisition resolves a revision and materialises a detached tree.
//// Options can not be passed through URLs or refs, and the `ext` transport, which runs commands, is disabled.

import filepath
import gleam/int
import gleam/option.{None, Some}
import gleam/string
import loam/system

/// Fetch into a fresh checkout, resolve the requested name to a commit, then
/// check out that commit detached. No branch is shared with another acquisition.
pub fn snapshot(
  url: String,
  ref: option.Option(String),
  path: String,
) -> system.Effect(Result(String, String)) {
  use Nil <- system.try(argument("url", url))
  use Nil <- system.try(case ref {
    Some(ref) -> argument("ref", ref)
    None -> Ok(Nil)
  })
  let parent = filepath.directory_name(path)
  use _ <- step(
    "clone",
    [
      "-c",
      "protocol.ext.allow=never",
      "-c",
      "core.hooksPath=/dev/null",
      "clone",
      "--no-checkout",
      "--no-local",
      "--quiet",
      "--",
      url,
      path,
    ],
    parent,
  )
  let candidates = case ref {
    None | Some("HEAD") -> ["HEAD"]
    Some("refs/heads/" <> branch) -> ["refs/remotes/origin/" <> branch]
    Some("refs/" <> _ as ref) -> [ref]
    Some(ref) -> ["refs/remotes/origin/" <> ref, "refs/tags/" <> ref, ref]
  }
  use commit <- system.then(resolve_commit(path, candidates))
  use commit <- system.try(commit)
  use _ <- step(
    "checkout",
    [
      "-C",
      path,
      "-c",
      "core.hooksPath=/dev/null",
      "-c",
      "core.autocrlf=false",
      "checkout",
      "--quiet",
      "--detach",
      commit,
    ],
    path,
  )
  system.Done(Ok(commit))
}

fn resolve_commit(path, candidates) {
  case candidates {
    [] -> system.Done(Error("repository revision was not found"))
    [ref, ..rest] -> {
      use resolved <- system.then(system.command(
        "git",
        [
          "-C",
          path,
          "rev-parse",
          "--verify",
          "--end-of-options",
          ref <> "^{commit}",
        ],
        path,
      ))
      case resolved {
        Ok(commit) -> system.Done(Ok(string.trim(commit)))
        Error(_) -> resolve_commit(path, rest)
      }
    }
  }
}

// Run one git command, stopping at the first failure.
fn step(
  name: String,
  arguments: List(String),
  directory: String,
  then: fn(String) -> system.Effect(Result(String, String)),
) -> system.Effect(Result(String, String)) {
  use output <- system.then(system.command("git", arguments, directory))
  case output {
    Ok(output) -> then(output)
    Error(#(status, output)) ->
      system.Done(Error(
        "git "
        <> name
        <> " failed with status "
        <> int.to_string(status)
        <> ": "
        <> string.trim(output),
      ))
  }
}

fn argument(name, value) {
  case string.starts_with(value, "-") {
    True -> Error("invalid " <> name <> ": " <> value)
    False -> Ok(Nil)
  }
}
