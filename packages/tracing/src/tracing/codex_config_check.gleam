//// Execute the Codex guide's configuration with fake credentials and no model turn.

import filepath
import glasshouse/archive
import glasshouse/rerun
import glasshouse/session
import gleam/dict
import gleam/io
import gleam/javascript/promise
import gleam/list
import gleam/option.{None, Some}
import gleam/result
import gleam/string
import plinthx/bun/runtime
import plinthx/bun/subprocess
import plinthx/node/process
import simplifile

pub fn main() {
  let assert Ok(_) = simplifile.create_directory_all("recordings")
  let assert Ok(cwd) = simplifile.current_directory()
  let root = filepath.join(cwd, "../..")
  let directory = filepath.join(cwd, ".recordings/codex-config")
  case simplifile.exists(directory, False) {
    Ok(True) -> {
      let assert Ok(_) = simplifile.delete(directory)
      Nil
    }
    _ -> Nil
  }
  let assert Ok(_) = simplifile.create_directory_all(directory)
  let assert Ok(bun) = runtime.get()
  let assert Ok(host) = process.get()
  let env = process.env(host) |> dict.from_list
  let binary =
    dict.get(env, "EYG_BIN")
    |> result.unwrap(filepath.join(root, "packages/gleam_cli/dist/eyg"))
  let env = env |> dict.insert("EYG_TRACE_DIR", directory) |> dict.to_list
  let assert Ok(child) =
    subprocess.spawn_with_input(
      bun,
      subprocess.Options(
        [binary, "overlay", "packages/tracing/fixtures/codex.eyg"],
        root,
        env,
        "pipe",
        "pipe",
        "pipe",
      ),
      <<"\n">>,
    )
  let assert Ok(stdout) = subprocess.stdout(child)
  let assert Ok(stderr) = subprocess.stderr(child)
  use output <- promise.await(subprocess.readable_stream_to_text(bun, stdout))
  use errors <- promise.await(subprocess.readable_stream_to_text(bun, stderr))
  use status <- promise.map(subprocess.exited(child))
  let assert Ok(errors) = errors
  let assert Ok(0) = status as errors
  let assert Ok(output) = output
  assert string.contains(output, "trace saved") as output
  let assert Ok(files) = simplifile.read_directory(directory)
  let assert [file] = files
  let assert Ok(text) = simplifile.read(filepath.join(directory, file))
  let assert Ok(saved) = archive.from_string(text)
  assert archive.missing(saved) == []
  let assert Some(agent) = saved.session.agent
  assert agent.provider == "openai-codex"
  assert session.generations(saved.session) == []
  assert !string.contains(text, "fixture-access-token-123")
  assert !string.contains(text, "fixture-refresh-token-123")
  assert !string.contains(text, "fixture-id-token-123")
  assert list.all(rerun.session(saved.session, saved.store), fn(report) {
    report.problem == None
  })
  let assert Ok(_) = simplifile.write("recordings/codex-config.json", text)
  io.println(
    "PASS compiled Codex configuration: fake file cache, secret redaction, archive closure and offline replay; no model request",
  )
}
