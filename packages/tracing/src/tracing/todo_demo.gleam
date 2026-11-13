//// Check and record the real Lustre TodoMVC with local hub/model fixtures.

import filepath
import gleam/http/request
import gleam/int
import gleam/io
import gleam/javascript/promise
import gleam/list
import gleam/string
import gleam_playwright as browser
import javascript/mutable_reference as reference
import loam/system
import plinthx/bun/runtime
import plinthx/bun/server
import plinthx/bun/subprocess
import plinthx/node/process
import plinthx/node/timers
import simplifile
import tracing/package_fixture
import tracing/record_browser
import tracing/scripted_model as model

pub fn main() {
  example("todomvc_lustre", "todomvc", 7820)
}

/// Run the same capability, UI and cache checks against either host boundary.
pub fn example(folder: String, recording: String, port: Int) {
  let origin = "http://127.0.0.1:" <> int.to_string(port)
  let assert Ok(cwd) = simplifile.current_directory()
  let root = filepath.join(cwd, "../..")
  let project = filepath.join(root, "examples/" <> folder)
  use installed <- promise.await(
    system.run(system.command(
      "bun",
      ["install"],
      filepath.join(root, "examples/todomvc_lustre"),
    )),
  )
  let assert Ok(_) = installed
  use sdk <- promise.await(
    system.run(system.command(
      "gleam",
      ["run", "-m", "build"],
      filepath.join(root, "packages/embed_js"),
    )),
  )
  let assert Ok(_) = sdk
  use built <- promise.await(
    system.run(system.command("gleam", ["run", "-m", "build"], project)),
  )
  let assert Ok(_) = built
  let assert Ok(hub) = package_fixture.start()
  let standard = hub.reference
  let model =
    model.start([
      model.Run(
        "let {list} = "
        <> standard
        <> " list.map(todos.complete, todos.tagged(\"#shopping\"))",
      ),
      model.Run(
        "let {list} = "
        <> standard
        <> " let _ = list.map(todos.tagged(\"#shopping\"), todos.complete) todos.add(\"Renew the car insurance #admin\")",
      ),
      model.Say(
        "Shopping is complete and the car insurance task is on your admin list.",
      ),
    ])
  let assert Ok(bun) = runtime.get()
  let assert Ok(host) = process.get()
  let env =
    process.env(host)
    |> list.filter(fn(pair) {
      pair.0 != "PORT" && pair.0 != "EYG_HUB" && pair.0 != "OLLAMA_ORIGIN"
    })
    |> list.append([
      #("PORT", int.to_string(port)),
      #("EYG_HUB", "http://127.0.0.1:7207"),
      #("OLLAMA_ORIGIN", model.origin),
    ])
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
      use _ <- promise.await(ready(origin, 100))
      record_browser.run(recording, fn(page) {
        walkthrough(page, origin, hub, model)
      })
    }
    |> promise.map(Ok)
    |> promise.rescue(Error)
  use outcome <- promise.await(outcome)
  let _ = subprocess.kill(app, "SIGTERM")
  use _ <- promise.await(subprocess.exited(app))
  use _ <- promise.await(server.stop(model.server, True))
  use _ <- promise.map(server.stop(hub.server, True))
  let assert Ok(_) = outcome
  io.println(
    "PASS TodoMVC tasks, typed shell, model correction, native controls and cache reuse",
  )
}

fn ready(origin, attempts) {
  assert attempts > 0 as "TodoMVC did not start"
  let assert Ok(request) = request.to(origin)
  use response <- promise.await(
    system.run(system.fetch(request.set_body(request, <<>>))),
  )
  case response {
    Ok(response) if response.status == 200 -> promise.resolve(Nil)
    _ -> {
      use _ <- promise.await(timers.sleep(100))
      ready(origin, attempts - 1)
    }
  }
}

fn done(work) {
  use result <- promise.map(work)
  let assert Ok(_) = result
  Nil
}

fn click(page, selector) {
  done(browser.click(browser.locator(page, selector)))
}

fn count(page, selector, expected) {
  done(browser.count(browser.locator(page, selector), expected))
}

fn text(page, selector, expected) {
  done(browser.contains(browser.locator(page, selector), expected))
}

fn run(page, code) {
  let input = browser.locator(page, "textarea[aria-label='EYG code']")
  use _ <- promise.await(done(browser.fill(input, code)))
  done(browser.press(input, "Control+Enter"))
}

fn walkthrough(
  page,
  origin,
  hub: package_fixture.Fixture,
  model: model.Fixture,
) {
  let errors = reference.new([])
  browser.on_error(page, fn(error) {
    reference.set(errors, [error, ..reference.get(errors)])
    Nil
  })
  use _ <- promise.await(done(browser.goto(page, origin)))
  use _ <- promise.await(count(page, ".console button[type=submit]:disabled", 0))
  use _ <- promise.await(count(page, ".todo-list > li", 5))
  assert hub.count() == 3
  use _ <- promise.await(timers.sleep(1000))

  use _ <- promise.await(run(
    page,
    "perform SetCompleted({id: \"1\", completed: True({})})",
  ))
  use _ <- promise.await(text(page, ".transcript", "nothing ran"))
  use _ <- promise.await(count(page, ".todo-list > li.completed", 0))
  use _ <- promise.await(timers.sleep(1300))

  use _ <- promise.await(run(
    page,
    "!list_fold([\"Pack passport #travel\", \"Book a taxi #travel\"], [], (title, ids) -> { [perform CreateTask(title), ..ids] })",
  ))
  use _ <- promise.await(count(page, ".todo-list > li", 7))
  use _ <- promise.await(text(page, ".todo-list", "Pack passport #travel"))
  use _ <- promise.await(timers.sleep(1000))

  use _ <- promise.await(run(page, "let {list} = " <> hub.reference <> "
let tags = list.fold(list.flat_map(todos.all({}), todos.tags), [], (tag, seen) -> {
  match list.contains(seen, tag) { True(_) -> { seen } False(_) -> { [tag, ..seen] } }
})
list.map(tags, (tag) -> { {tag, count: list.length(todos.tagged(tag))} })"))
  use _ <- promise.await(text(page, ".transcript", "count: 2"))
  use _ <- promise.await(timers.sleep(1300))

  use _ <- promise.await(run(
    page,
    "let {list, string} = "
      <> hub.reference
      <> " list.map(todos.matching(\"plumber\"), (task) -> { todos.rename(task, string.append(\"Urgent: \", task.title)) })",
  ))
  use _ <- promise.await(text(page, ".todo-list", "Urgent: Call the plumber"))
  use _ <- promise.await(run(
    page,
    "perform ReadFile({path: \"unused\", offset: 0, limit: 1000})",
  ))
  use _ <- promise.await(text(page, ".transcript", "missing row 'ReadFile'"))
  use _ <- promise.await(count(page, ".todo-list > li", 7))
  assert hub.count() == 3
  use _ <- promise.await(timers.sleep(1000))

  use _ <- promise.await(
    done(browser.fill(browser.locator(page, ".new-todo"), "Mouse task #demo")),
  )
  use _ <- promise.await(
    done(browser.press(browser.locator(page, ".new-todo"), "Enter")),
  )
  use _ <- promise.await(count(page, ".todo-list > li", 8))
  use _ <- promise.await(click(
    page,
    ".todo-list li:has-text('Mouse task') .toggle",
  ))
  use _ <- promise.await(count(page, ".todo-list > li.completed", 1))
  use _ <- promise.await(click(page, ".filters a[href='#/completed']"))
  use _ <- promise.await(count(page, ".todo-list > li", 1))
  use _ <- promise.await(click(page, ".filters a[href='#/active']"))
  use _ <- promise.await(count(page, ".todo-list > li", 7))
  use _ <- promise.await(click(page, ".filters a[href='#/']"))
  use _ <- promise.await(count(page, ".todo-list > li", 8))
  use _ <- promise.await(
    done(
      browser.double_click(browser.locator(
        page,
        ".todo-list li:has-text('Mouse task') label",
      )),
    ),
  )
  use _ <- promise.await(
    done(browser.fill(
      browser.locator(page, ".todo-list li.editing .edit"),
      "Renamed task #demo",
    )),
  )
  use _ <- promise.await(
    done(browser.press(
      browser.locator(page, ".todo-list li.editing .edit"),
      "Enter",
    )),
  )
  use _ <- promise.await(
    done(
      browser.hover(browser.locator(
        page,
        ".todo-list li:has-text('Renamed task')",
      )),
    ),
  )
  use _ <- promise.await(click(
    page,
    ".todo-list li:has-text('Renamed task') .destroy",
  ))
  use _ <- promise.await(count(page, ".todo-list > li", 7))
  use _ <- promise.await(count(page, ".todo-list > li.completed", 0))

  use _ <- promise.await(click(page, ".tabs button:has-text('Agent')"))
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
      "Mark my shopping complete and add the car insurance task.",
    )),
  )
  use _ <- promise.await(click(page, ".prompt button[type=submit]"))
  use _ <- promise.await(text(page, ".transcript", "Shopping is complete"))
  use _ <- promise.await(count(page, ".run.by-model.failed", 1))
  use _ <- promise.await(count(page, ".todo-list > li.completed", 2))
  use _ <- promise.await(count(page, ".todo-list > li", 8))
  use _ <- promise.await(text(
    page,
    ".todo-list",
    "Renew the car insurance #admin",
  ))
  assert model.count() == 3
  assert list.any(model.requests(), string.contains(_, "nothing ran"))
  assert hub.count() == 3
  use _ <- promise.await(timers.sleep(2000))

  use _ <- promise.await(click(page, ".clear-completed"))
  use _ <- promise.await(count(page, ".todo-list > li", 6))
  use _ <- promise.await(click(page, ".toggle-all-label"))
  use _ <- promise.await(count(page, ".todo-list > li.completed", 6))
  use _ <- promise.await(click(page, ".toggle-all-label"))
  use _ <- promise.await(count(page, ".todo-list > li.completed", 0))
  use _ <- promise.map(timers.sleep(2000))
  assert reference.get(errors) == []
}
