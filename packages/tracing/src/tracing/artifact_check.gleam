//// Run the real artifact workflows against a caller-owned PostgreSQL database.
//// Own process groups keep the hub and Vite children bounded to this check.

import filepath
import gleam/dict
import gleam/dynamic/decode
import gleam/int
import gleam/io
import gleam/javascript/promise
import gleam/option.{Some}
import gleam/result
import plinthx/browser/abort_signal
import plinthx/browser/fetch
import plinthx/bun/runtime
import plinthx/bun/subprocess
import plinthx/javascript/foreign
import plinthx/node/process
import plinthx/node/timers
import simplifile
import tracing/host

fn with_server(arguments, directory, env, log, work) {
  let assert Ok(bun) = runtime.get()
  let assert Ok(child) =
    subprocess.spawn(
      bun,
      subprocess.Options(
        ["setsid", ..arguments],
        directory,
        env,
        "ignore",
        "pipe",
        "pipe",
      ),
    )
  let assert Ok(pid) =
    foreign.property(foreign.to_dynamic(child), "pid") |> decode.run(decode.int)
  let assert Ok(stdout) = subprocess.stdout(child)
  let assert Ok(stderr) = subprocess.stderr(child)
  let output = subprocess.readable_stream_to_text(bun, stdout)
  let errors = subprocess.readable_stream_to_text(bun, stderr)
  let checked =
    promise.resolve(Nil)
    |> promise.await(fn(_) { work() })
    |> promise.map(Ok)
    |> promise.rescue(Error)
  use checked <- promise.await(checked)
  use _ <- promise.await(
    host.command(["kill", "-TERM", "--", "-" <> int.to_string(pid)], ".", []),
  )
  use _ <- promise.await(timers.sleep(150))
  use _ <- promise.await(
    host.command(["kill", "-KILL", "--", "-" <> int.to_string(pid)], ".", []),
  )
  use _ <- promise.await(subprocess.exited(child))
  use output <- promise.await(output)
  use errors <- promise.map(errors)
  let assert Ok(_) =
    simplifile.write(
      log,
      result.unwrap(output, "") <> result.unwrap(errors, ""),
    )
  case checked {
    Ok(_) -> Nil
    Error(error) -> foreign.raise(error)
  }
}

fn ready(url, expected_status, remaining) {
  let assert Ok(client) = fetch.get()
  let assert Ok(signals) = abort_signal.get()
  let assert Ok(timeout) = abort_signal.timeout(signals, 1000)
  use response <- promise.await(fetch.send(
    client,
    url,
    fetch.RequestInit("GET", [], "", Some(timeout)),
  ))
  case response {
    Ok(response) ->
      case fetch.status(response) == expected_status {
        True -> promise.resolve(Nil)
        False -> retry(url, expected_status, remaining)
      }
    Error(_) -> retry(url, expected_status, remaining)
  }
}

fn retry(url, expected_status, remaining) {
  assert remaining > 0 as { "server did not become ready: " <> url }
  use _ <- promise.await(timers.sleep(200))
  ready(url, expected_status, remaining - 1)
}

pub fn main() {
  let assert Ok(cwd) = simplifile.current_directory()
  let root = filepath.join(cwd, "../..")
  let assert Ok(host_process) = process.get()
  let env =
    dict.merge(
      dict.from_list(process.env(host_process)),
      dict.from_list([
        #("PORT", "7812"),
        #("EYG_HUB", "http://127.0.0.1:7812"),
        #("EYG_OLLAMA", "http://127.0.0.1:7201"),
        #("ERL_FLAGS", "+S 2:2"),
        #("DEMO_OUTPUT_DIR", ".recordings/artifact-check"),
      ]),
    )
    |> dict.to_list
  let assert Ok(_) = simplifile.create_directory_all(".recordings")
  use migrated <- promise.await(host.command(
    ["gleam", "run", "-m", "hub_dev", "--", "migrate"],
    root <> "/packages/hub",
    env,
  ))
  let assert Ok(migrated) = migrated
  assert migrated.status == 0 as { migrated.stdout <> migrated.stderr }
  with_server(
    ["gleam", "run"],
    root <> "/packages/hub",
    env,
    ".recordings/artifact-hub.log",
    fn() {
      use _ <- promise.await(ready("http://127.0.0.1:7812", 404, 100))
      with_server(
        [
          "bun",
          "run",
          "dev",
          "--",
          "--host",
          "127.0.0.1",
          "--port",
          "5280",
          "--strictPort",
        ],
        root <> "/packages/overlay_public",
        env,
        ".recordings/artifact-ui.log",
        fn() {
          use _ <- promise.await(ready(
            "http://127.0.0.1:5280/overlay/",
            200,
            100,
          ))
          use checked <- promise.await(host.command(
            ["gleam", "run", "-m", "tracing/artifact_demo"],
            cwd,
            env,
          ))
          let assert Ok(checked) = checked
          assert checked.status == 0 as { checked.stdout <> checked.stderr }
          io.println(checked.stdout)
          use checked <- promise.map(host.command(
            ["gleam", "run", "-m", "tracing/viewer_demo"],
            cwd,
            env,
          ))
          let assert Ok(checked) = checked
          assert checked.status == 0 as { checked.stdout <> checked.stderr }
          io.println(checked.stdout)
          io.println(
            "PASS real artifact checks: saved workspaces, sharing, preview isolation and typed browser controls",
          )
        },
      )
    },
  )
}
