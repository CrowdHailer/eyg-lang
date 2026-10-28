//// Execute the sandbox guide, export its cohort and verify complete offline replay.

import eyg/cli/evaluate
import eyg/cli/inspect
import eyg/cli/internal/client
import eyg/cli/internal/config
import eyg/cli/internal/traces
import eyg/cli/sandbox
import glasshouse/archive
import glasshouse/cohort
import glasshouse/rerun
import glasshouse/session
import glasshouse_mock
import glasshouse_mock/langfuse
import glasshouse_mock/model
import glasshouse_mock/neon
import glasshouse_mock/server
import gleam/io
import gleam/javascript/promise
import gleam/list
import gleam/option.{None}
import gleam/result
import gleam/string
import loam/os
import loam/source
import loam/system
import ogre/origin
import plinthx/bun/server as native_server
import simplifile

pub fn main() {
  let assert Ok(script) = simplifile.read("demo/script.json")
  let assert Ok(rules) = model.parse(script)
  let assert Ok(sql) = simplifile.read("demo/seed.sql")
  let assert Ok(database) = neon.seed(neon.new(), sql, 0)
  let state = glasshouse_mock.State(langfuse.new(), rules, database)
  let assert Ok(server) =
    server.start_server(4400, state, glasshouse_mock.handle)
  let outcome =
    system.run(workflow()) |> promise.map(Ok) |> promise.rescue(Error)
  use outcome <- promise.await(outcome)
  use stopped <- promise.await(native_server.stop(server, True))
  let assert Ok(_) = stopped
  let assert Ok(Ok(_)) = outcome
  let config =
    config.Config(
      client.Client(origin.https("eyg.run")),
      os.Directories("", "", ""),
      False,
    )
  use replayed <- promise.map(
    system.run(sandbox.replay("demo/.eyg/export/session.json", config)),
  )
  let assert Ok(0) = replayed
  io.println(
    "PASS sandbox guide: private report, full offline replay, cohort and portable exports",
  )
}

fn workflow() {
  let config =
    config.Config(
      client.Client(origin.https("eyg.run")),
      os.Directories("", "", ""),
      False,
    )
  let output = "demo/.eyg/export"
  use created <- system.then(system.create_directory(output))
  use Nil <- system.try(created)
  use prepared <- system.then(sandbox.prepare(
    "demo/project",
    ".overlay.eyg",
    "demo/.eyg/environment.json",
    config,
  ))
  use code <- system.try(prepared)
  let assert 0 = code
  use runs <- system.then(system.temporary_directory())
  use runs <- system.try(runs)
  use executed <- system.then(sandbox.execute(
    "demo/.eyg/environment.json",
    ".overlay.eyg",
    runs,
    sandbox.Agent,
    ["Write the signups report"],
    ["localhost"],
    config,
  ))
  use code <- system.try(executed)
  let assert 0 = code
  use files <- system.then(system.read_directory(runs))
  use files <- system.try(result.replace_error(
    files,
    "could not list demo traces",
  ))
  use name <- system.try(
    list.find(files, fn(file) { string.ends_with(file, ".json") })
    |> result.replace_error("missing baseline trace"),
  )
  let trace = runs <> "/" <> name
  use inspected <- system.then(inspect.execute(trace, None, config))
  use code <- system.try(inspected)
  let assert 0 = code
  use replayed <- system.then(sandbox.replay(trace, config))
  use code <- system.try(replayed)
  let assert 0 = code
  use evaluated <- system.then(evaluate.execute(
    trace,
    source.File("demo/variants.eyg"),
    config,
  ))
  use code <- system.try(evaluated)
  let assert 0 = code
  use exported <- system.then(sandbox.export(trace, output <> "/session.json"))
  use code <- system.try(exported)
  let assert 0 = code
  use exported <- system.then(sandbox.snapshot(
    trace,
    output <> "/environment.json",
  ))
  use code <- system.try(exported)
  let assert 0 = code
  let id = string.drop_end(name, 5)
  use exported <- system.then(
    system.traverse(
      ["same", "with-totals", "blog-only", "check-the-website"],
      fn(name) {
        sandbox.export(
          runs <> "/" <> id <> "-" <> name <> ".json",
          output <> "/" <> name <> ".json",
        )
      },
    ),
  )
  use _ <- system.try(result.all(exported))
  use report <- system.then(system.read_file(
    runs <> "/" <> id <> ".cohort.json",
  ))
  use report <- system.try(report)
  use written <- system.then(system.write_file(output <> "/cohort.json", report))
  use Nil <- system.try(written)
  use baseline <- system.then(traces.load(trace))
  use baseline <- system.try(baseline)
  use Nil <- system.try(case cohort.stopped(baseline.session) {
    None -> Ok(Nil)
    _ -> Error("baseline stopped")
  })
  let reports = rerun.session(baseline.session, baseline.store)
  use Nil <- system.try(
    case list.all(reports, fn(report) { report.problem == None }) {
      True -> Ok(Nil)
      False -> Error("journal replay diverged")
    },
  )
  use Nil <- system.try(
    case
      archive.missing(baseline) == []
      && session.generations(baseline.session) != []
    {
      True -> Ok(Nil)
      False -> Error("incomplete baseline")
    },
  )
  use present <- system.then(system.file_info("demo/project/reports/signups.md"))
  use Nil <- system.try(case present {
    Error(_) -> Ok(Nil)
    Ok(_) -> Error("sandbox wrote a host report")
  })
  use cleaned <- system.map(system.delete_file(runs))
  result.replace_error(cleaned, "could not remove demo scratch traces")
}
