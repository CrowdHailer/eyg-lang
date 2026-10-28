//// Execute both documented puzzle sessions with a real game and scripted model.

import filepath
import gleam/http/request
import gleam/io
import gleam/javascript/promise
import gleam/list
import gleam/string
import gleam_playwright as browser
import javascript/mutable_reference as reference
import loam/system
import otel
import plinthx/bun/runtime
import plinthx/bun/server
import plinthx/bun/subprocess
import plinthx/node/process
import plinthx/node/timers
import simplifile
import tracing/record_browser
import tracing/scripted_model as model

const origin = "http://127.0.0.1:7822"

pub fn main() {
  let assert Ok(cwd) = simplifile.current_directory()
  let project = filepath.join(cwd, "../../examples/hashi")
  let env = otel.environment()
  use fetched <- promise.await(
    system.run(system.command(
      otel.env_value(env, "EYG_BIN", "eyg"),
      ["script", "bin/fetch_style.eyg"],
      project,
    )),
  )
  let assert Ok(_) = fetched
  use built <- promise.await(
    system.run(system.command("gleam", ["run", "-m", "build"], project)),
  )
  let assert Ok(_) = built
  let assert Ok(solver) = simplifile.read(filepath.join(project, "solver.eyg"))
  let model =
    model.start([
      model.Run("hashi.islands({})"),
      model.Run(
        "let middle = {x: 3, y: 3} perform AddBridge({form: middle, to: {x: 5, y: 3}})",
      ),
      model.Run(
        "let middle = {x: 3, y: 3}
let _ = hashi.connect(middle, {x: 5, y: 3})
let _ = hashi.connect(middle, {x: 5, y: 3})
let _ = hashi.connect(middle, {x: 3, y: 1})
hashi.connect(middle, {x: 3, y: 1})",
      ),
      model.Run(solver <> "\nsolve({})"),
      model.Say(
        "The puzzle is solved. I corrected the field name and played the forced bridges.",
      ),
    ])
  let assert Ok(bun) = runtime.get()
  let assert Ok(host) = process.get()
  let env =
    process.env(host)
    |> list.filter(fn(pair) { pair.0 != "PORT" && pair.0 != "OLLAMA_ORIGIN" })
    |> list.append([#("PORT", "7822"), #("OLLAMA_ORIGIN", model.origin)])
  let assert Ok(app) =
    subprocess.spawn(
      bun,
      subprocess.Options(
        ["bun", "run", "dist/serve.mjs"],
        project,
        env,
        "ignore",
        "pipe",
        "pipe",
      ),
    )
  let outcome =
    {
      use _ <- promise.await(ready(100))
      record_browser.run("hashi", fn(page) { walkthrough(page, solver, model) })
    }
    |> promise.map(Ok)
    |> promise.rescue(Error)
  use outcome <- promise.await(outcome)
  let _ = subprocess.kill(app, "SIGTERM")
  use _ <- promise.await(subprocess.exited(app))
  use _ <- promise.map(server.stop(model.server, True))
  let assert Ok(_) = outcome
  io.println(
    "PASS real Hashi shell, retained solver, type rejection, agent correction and solved boards",
  )
}

fn ready(attempts) {
  assert attempts > 0
  let assert Ok(request) = request.to(origin)
  use response <- promise.await(
    system.run(system.fetch(request.set_body(request, <<>>))),
  )
  case response {
    Ok(response) if response.status == 200 -> promise.resolve(Nil)
    _ -> {
      use _ <- promise.await(timers.sleep(100))
      ready(attempts - 1)
    }
  }
}

fn done(work) {
  use result <- promise.map(work)
  let assert Ok(_) = result
  Nil
}

fn run(page, code) {
  let input = browser.locator(page, "textarea[aria-label='EYG code']")
  use _ <- promise.await(done(browser.fill(input, code)))
  done(browser.press(input, "Control+Enter"))
}

fn walkthrough(page, solver, model: model.Fixture) {
  let errors = reference.new([])
  browser.on_error(page, fn(error) {
    reference.set(errors, [error, ..reference.get(errors)])
    Nil
  })
  use _ <- promise.await(done(browser.goto(page, origin <> "/?seed=1")))
  use _ <- promise.await(
    done(browser.count(browser.locator(page, ".hashi-island"), 12)),
  )
  use _ <- promise.await(timers.sleep(1200))
  use _ <- promise.await(run(page, "hashi.with_target(6)"))
  use _ <- promise.await(
    done(browser.contains(browser.locator(page, ".transcript"), "target: 6")),
  )
  use _ <- promise.await(timers.sleep(1000))
  use _ <- promise.await(run(
    page,
    "perform ReadFile({path: \"unused\", offset: 0, limit: 1})",
  ))
  use _ <- promise.await(
    done(browser.contains(browser.locator(page, ".transcript"), "nothing ran")),
  )
  use _ <- promise.await(
    done(browser.count(browser.locator(page, ".hashi-bridge"), 0)),
  )
  use _ <- promise.await(run(
    page,
    "let big = hashi.with_target(6)
hashi.each(big, (island) -> {
  hashi.each(hashi.neighbours(island), (other) -> {
    let _ = hashi.connect(island, other)
    hashi.connect(island, other)
  })
})",
  ))
  use _ <- promise.await(timers.sleep(1600))
  use _ <- promise.await(run(page, solver))
  use _ <- promise.await(run(page, "solve({})"))
  use _ <- promise.await(
    done(browser.contains(browser.locator(page, ".solved"), "Solved!")),
  )
  use _ <- promise.await(
    done(browser.count(browser.locator(page, ".hashi-grid.complete"), 1)),
  )
  use _ <- promise.await(timers.sleep(2200))

  use _ <- promise.await(done(browser.goto(page, origin <> "/?seed=3")))
  use _ <- promise.await(
    done(browser.click(browser.locator(page, ".tabs button:has-text('Agent')"))),
  )
  use _ <- promise.await(
    done(browser.fill(
      browser.locator(page, "input[aria-label='Model']"),
      "scripted-fixture",
    )),
  )
  use _ <- promise.await(
    done(browser.press(
      browser.locator(page, "input[aria-label='Model']"),
      "Tab",
    )),
  )
  use _ <- promise.await(
    done(browser.fill(
      browser.locator(page, "textarea[aria-label='Message']"),
      "Please solve the puzzle.",
    )),
  )
  use _ <- promise.await(
    done(browser.click(browser.locator(page, ".prompt button"))),
  )
  use _ <- promise.await(
    done(browser.contains(
      browser.locator(page, ".transcript"),
      "I corrected the field name",
    )),
  )
  use _ <- promise.await(
    done(browser.count(browser.locator(page, ".run.by-model.failed"), 1)),
  )
  use _ <- promise.await(
    done(browser.contains(browser.locator(page, ".solved"), "Solved!")),
  )
  use _ <- promise.map(timers.sleep(2500))
  assert model.count() == 5
  assert list.any(model.requests(), string.contains(_, "nothing ran"))
  assert reference.get(errors) == []
}
