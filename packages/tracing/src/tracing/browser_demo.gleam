//// Exercise the guide against a scripted model and the actual browser applications.

import filepath
import glasshouse/archive
import glasshouse/rerun
import glasshouse/session
import gleam/dynamic/decode
import gleam/io
import gleam/javascript/promise
import gleam/list
import gleam/option.{None}
import gleam/result
import gleam/string
import gleam_playwright as browser
import otel
import plinthx/bun/server
import simplifile
import tracing/model_fixture

pub fn main() {
  let assert Ok(server) = model_fixture.start()
  let outcome = run() |> promise.map(Ok) |> promise.rescue(Error)
  use outcome <- promise.await(outcome)
  use stopped <- promise.map(server.stop(server, True))
  assert stopped == Ok(Nil)
  case outcome {
    Ok(_) ->
      io.println(
        "Browser recording, archive closure and offline replay verified.",
      )
    Error(reason) -> panic as failure(reason)
  }
}

fn run() {
  let env = otel.environment()
  let output_directory = otel.env_value(env, "DEMO_OUTPUT_DIR", "recordings")
  let executable = otel.env_value(env, "CHROME_BIN", "")
  let assert Ok(_) = simplifile.create_directory_all(".recordings")
  let assert Ok(_) = simplifile.create_directory_all(output_directory)
  use launched <- promise.await(browser.launch(executable, 150))
  let assert Ok(launched) = launched
  use context <- promise.await(browser.context(
    launched,
    ".recordings",
    1280,
    800,
  ))
  let assert Ok(context) = context
  use page <- promise.await(browser.page(context))
  let assert Ok(page) = page
  browser.on_error(page, io.print_error)
  browser.on_console(page, io.print_error)
  let video = browser.video(page)
  let outcome =
    walkthrough(page, output_directory)
    |> promise.map(Ok)
    |> promise.rescue(Error)
  use outcome <- promise.await(outcome)
  use html <- promise.await(browser.content(page))
  let assert Ok(_) = simplifile.write(".recordings/page.html", html)
  use screenshot <- promise.await(
    browser.screenshot(page, case outcome {
      Ok(_) -> filepath.join(output_directory, "trajectories.png")
      Error(_) -> ".recordings/failed.png"
    }),
  )
  let assert Ok(_) = screenshot
  use closed <- promise.await(browser.close_context(context))
  let assert Ok(_) = closed
  use saved <- promise.await(
    browser.save_video(video, case outcome {
      Ok(_) -> filepath.join(output_directory, "trajectories.webm")
      Error(_) -> ".recordings/failed.webm"
    }),
  )
  let assert Ok(_) = saved
  use closed <- promise.map(browser.close_browser(launched))
  let assert Ok(_) = closed
  case outcome {
    Ok(_) -> Nil
    Error(reason) -> panic as failure(reason)
  }
}

fn failure(reason) {
  let location =
    decode.optional_field("file", "", decode.string, decode.success)
  let value = decode.field("value", decode.dynamic, decode.success)
  let location = decode.run(reason, location) |> result.unwrap("")
  let details =
    decode.run(reason, value)
    |> result.map(string.inspect)
    |> result.unwrap(string.inspect(reason))
  location <> ": " <> details
}

fn walkthrough(page: browser.Page, output_directory: String) {
  use done <- promise.await(browser.goto(page, "http://127.0.0.1:5280/overlay/"))
  let assert Ok(_) = done
  // The first visit opens provider settings after tab storage is restored.
  use done <- promise.await(browser.contains(
    browser.locator(page, ".provider-panel"),
    "LLM connection",
  ))
  let assert Ok(_) = done
  use done <- promise.await(browser.select_option(
    browser.locator(page, "select[name=provider]"),
    "ollama",
  ))
  let assert Ok(_) = done
  use done <- promise.await(browser.fill(
    browser.locator(page, "input[name=api-token]"),
    "local-demo-token",
  ))
  let assert Ok(_) = done
  use done <- promise.await(
    browser.click(browser.locator(page, ".provider-save")),
  )
  let assert Ok(_) = done
  use done <- promise.await(browser.fill(
    browser.locator(page, ".chat-input textarea"),
    "Add 2 and 3 and print the result.",
  ))
  let assert Ok(_) = done
  use done <- promise.await(browser.press(
    browser.locator(page, ".chat-input textarea"),
    "Enter",
  ))
  let assert Ok(_) = done
  use done <- promise.await(browser.contains(
    browser.locator(page, ".messages"),
    "Computed 5.",
  ))
  let assert Ok(_) = done
  use done <- promise.await(browser.contains(
    browser.locator(page, ".trace-runs"),
    "Print",
  ))
  let assert Ok(_) = done
  use done <- promise.await(browser.fill(
    browser.locator(page, ".chat-input textarea"),
    "Read your trace.",
  ))
  let assert Ok(_) = done
  use done <- promise.await(browser.press(
    browser.locator(page, ".chat-input textarea"),
    "Enter",
  ))
  let assert Ok(_) = done
  use done <- promise.await(browser.contains(
    browser.locator(page, ".messages"),
    "Read the recorded trajectory.",
  ))
  let assert Ok(_) = done
  let downloaded = browser.download(page)
  use done <- promise.await(
    browser.click(browser.locator(page, ".trace-download")),
  )
  let assert Ok(_) = done
  use downloaded <- promise.await(downloaded)
  let assert Ok(downloaded) = downloaded
  let assert Ok(cwd) = simplifile.current_directory()
  let archive_path =
    filepath.join(cwd, filepath.join(output_directory, "trajectory.json"))
  use done <- promise.await(browser.save_download(downloaded, archive_path))
  let assert Ok(_) = done
  let assert Ok(text) = simplifile.read(archive_path)
  let assert Ok(archived) = archive.from_string(text)
  assert archive.missing(archived) == []
  assert list.length(session.generations(archived.session)) == 4
  let reports = rerun.session(archived.session, archived.store)
  assert list.length(reports) == 3
  assert list.all(reports, fn(report) { report.problem == None })
  use done <- promise.await(browser.goto(
    page,
    "http://127.0.0.1:7201/glasshouse/debugger/",
  ))
  let assert Ok(_) = done
  use done <- promise.await(browser.set_input_files(
    browser.locator(page, "input[type=file]"),
    archive_path,
  ))
  let assert Ok(_) = done
  use done <- promise.await(
    browser.click(browser.locator(page, "button:text-is('Replay')")),
  )
  let assert Ok(_) = done
  use done <- promise.await(
    browser.click(browser.locator(
      page,
      "button:text-is('Replay trajectory.json')",
    )),
  )
  let assert Ok(_) = done
  use done <- promise.map(browser.contains(
    browser.locator(page, ".gh-replay-summary"),
    "3 runs reproduced exactly",
  ))
  let assert Ok(_) = done
}
