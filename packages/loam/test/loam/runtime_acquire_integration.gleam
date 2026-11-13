//// Real Git integration, isolated in host temporary directories. Run with:
//// gleam run -m loam/runtime_acquire_integration --target javascript --runtime bun

import eyg/hub/cache
import eyg/interpreter/cast
import glasshouse/bundle
import glasshouse/sha256
import glasshouse/store
import gleam/io
import gleam/javascript/promise
import gleam/json
import gleam/option.{Some}
import gleam/result
import gleam/string
import loam/acquire
import loam/broker
import loam/environment
import loam/execute
import loam/sandbox/fs
import loam/source
import loam/system
import loam/virtual
import simplifile

pub fn main() {
  let workflow = {
    use directory <- system.then(system.temporary_directory())
    use directory <- system.try(directory)
    use tested <- system.then(exercise(directory))
    use cleaned <- system.map(system.delete_file(directory))
    use Nil <- result.try(result.replace_error(
      cleaned,
      "integration cleanup failed",
    ))
    tested
  }
  use tested <- promise.map(system.run(workflow))
  let assert Ok(Nil) = tested
  io.println(
    "PASS real Git: master A -> B, private edits, ordered offline replay after repository deletion",
  )
}

fn git(directory, args) {
  use returned <- system.map(system.command("git", args, directory))
  returned |> result.map(string.trim) |> result.map_error(fn(error) { error.1 })
}

fn commit(repo, message) {
  git(repo, [
    "-C",
    repo,
    "-c",
    "user.name=Sandbox integration",
    "-c",
    "user.email=sandbox@example.test",
    "-c",
    "commit.gpgSign=false",
    "-c",
    "core.hooksPath=/dev/null",
    "commit",
    "--quiet",
    "-am",
    message,
  ])
}

fn exercise(directory) {
  let repo = directory <> "/origin"
  use created <- system.then(system.create_directory(repo))
  use Nil <- system.try(created)
  use initialised <- system.then(
    git(repo, [
      "-c",
      "init.templateDir=",
      "init",
      "--quiet",
      "--initial-branch=master",
      repo,
    ]),
  )
  use _ <- system.try(initialised)
  use written <- system.then(system.write_file(repo <> "/file.txt", "A"))
  use Nil <- system.try(written)
  use added <- system.then(git(repo, ["-C", repo, "add", "file.txt"]))
  use _ <- system.try(added)
  use committed <- system.then(commit(repo, "A"))
  use _ <- system.try(committed)
  use first_commit <- system.then(git(repo, ["-C", repo, "rev-parse", "HEAD"]))
  use first_commit <- system.try(first_commit)

  let code =
    "let request = {source: Git({url: "
    <> json.to_string(json.string(repo))
    <> ", ref: Some(\"master\")}), expected: None({})}
let first = match perform Acquire(request) { Ok(receipt) -> { receipt } Error(reason) -> { !never(perform Abort(reason)) } }
let _ = perform Mount({root: first.root, path: \"first\"})
let _ = perform WriteFile({path: \"first/file.txt\", contents: !string_to_binary(\"private edit\")})
let second = match perform Acquire(request) { Ok(receipt) -> { receipt } Error(reason) -> { !never(perform Abort(reason)) } }
let conflict = perform Mount({root: second.root, path: \"first\"})
let _ = perform Mount({root: second.root, path: \"second\"})
{first, second, conflict}"
  use node <- system.try(source.parse(code, source.Inline))
  let environment =
    environment.Environment(
      ..environment.new(),
      files: fs.directory([#("workspace", fs.directory([]))]),
    )
  let state = execute.State(environment.hub, cache.empty(), option.None)
  let base = virtual.fork(environment)
  let machine = virtual.with_broker(base, broker.Live(["git:file:" <> repo]))
  // Simulate a push between the two identical requests. This is trusted test
  // infrastructure; the EYG program never receives a subprocess capability.
  let fetcher = fn(input) {
    use receipt <- system.then(acquire.perform(input))
    use receipt <- system.try(receipt)
    use advanced <- system.then(system.file_info(directory <> "/advanced"))
    case advanced {
      Error(simplifile.Enoent) -> {
        use written <- system.then(system.write_file(repo <> "/file.txt", "B"))
        use Nil <- system.try(written)
        use committed <- system.then(commit(repo, "B"))
        use _ <- system.try(committed)
        use marked <- system.then(system.write_file(
          directory <> "/advanced",
          "yes",
        ))
        use Nil <- system.try(marked)
        system.Done(Ok(receipt))
      }
      _ -> system.Done(Ok(receipt))
    }
  }
  let machine = virtual.Machine(..machine, fetcher:)
  use #(executed, machine) <- system.then(virtual.run(
    execute.block(node, [], state),
    machine,
  ))
  let assert Ok(#(Ok(#(Some(value), _)), _)) = executed
  let assert Ok(first) = cast.field("first", Ok, value)
  let assert Ok(second) = cast.field("second", Ok, value)
  assert cast.field("resolved", cast.as_string, first) == Ok(first_commit)
  use second_commit <- system.then(git(repo, ["-C", repo, "rev-parse", "HEAD"]))
  use second_commit <- system.try(second_commit)
  assert first_commit != second_commit
  assert cast.field("resolved", cast.as_string, second) == Ok(second_commit)
  assert fs.read(machine.file_system, "/workspace/first/file.txt")
    == Ok("private edit")
  assert fs.read(machine.file_system, "/workspace/second/file.txt") == Ok("B")
  let #(blocks, root) = broker.save(machine.broker, store.new())
  use exported <- system.try(bundle.from_string(
    bundle.to_string(bundle.new(root, blocks)),
    sha256.hash,
  ))
  use observations <- system.try(broker.load(exported.root, exported.store))
  use removed <- system.then(system.delete_file(repo))
  use Nil <- system.try(result.replace_error(
    removed,
    "failed to remove source repository",
  ))
  let replay = virtual.with_broker(base, broker.Replay(observations))
  let replay =
    virtual.Machine(..replay, fetcher: fn(_) {
      panic as "offline replay invoked Git"
    })
  use #(repeated, replay) <- system.map(virtual.run(
    execute.block(node, [], state),
    replay,
  ))
  let assert Ok(#(Ok(#(Some(repeated), _)), _)) = repeated
  assert repeated == value
  assert replay.file_system == machine.file_system
  Ok(Nil)
}
