//// Exercise previews, sharing, immutable revisions, recovery and portable files.

import filepath
import glasshouse/archive
import glasshouse/rerun
import glasshouse/session
import gleam/io
import gleam/javascript/promise
import gleam/list
import gleam/option.{None}
import gleam_playwright as browser
import otel
import plinthx/bun/server
import simplifile
import tracing/artifact_fixture
import tracing/record_browser

pub fn main() {
  let assert Ok(fixture) = artifact_fixture.start()
  let outcome =
    record_browser.run("artifacts", walkthrough)
    |> promise.map(Ok)
    |> promise.rescue(Error)
  use outcome <- promise.await(outcome)
  use stopped <- promise.map(server.stop(fixture, True))
  let assert Ok(_) = stopped
  let assert Ok(_) = outcome
  io.println(
    "PASS artifact guide: controls, screenshot, revisions, sharing, recovery, import/export and trajectory replay",
  )
}

fn walkthrough(page) {
  browser.on_error(page, io.print_error)
  browser.on_console(page, io.print_error)
  use done <- promise.await(browser.goto(page, "http://127.0.0.1:5280/overlay/"))
  let assert Ok(_) = done
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
  use _ <- promise.await(prompt(
    page,
    "Create a field notebook.",
    "Created the notebook and checked its preview.",
  ))
  use done <- promise.await(browser.contains(
    browser.locator(page, ".trace-runs"),
    "Puppet",
  ))
  let assert Ok(_) = done
  // A failed screenshot still produces a tool reply; require the actual image attachment.
  use done <- promise.await(browser.count(
    browser.locator(page, ".messages img"),
    1,
  ))
  let assert Ok(_) = done
  use done <- promise.await(
    browser.click(browser.locator(
      page,
      ".artifact-panel button:text-is('share')",
    )),
  )
  let assert Ok(_) = done
  use done <- promise.await(browser.contains(
    browser.locator(page, ".artifact-panel"),
    "shared ↗",
  ))
  let assert Ok(_) = done
  use first_link <- promise.await(browser.attribute(
    browser.locator(page, ".artifact-share"),
    "href",
  ))
  let assert Ok(first_link) = first_link
  use _ <- promise.await(prompt(
    page,
    "Revise the notebook.",
    "Revised the notebook and checked its preview.",
  ))
  use done <- promise.await(browser.contains(
    browser.locator(page, ".artifact-panel"),
    "v2",
  ))
  let assert Ok(_) = done
  use done <- promise.await(
    browser.click(browser.locator(
      page,
      ".artifact-panel button:text-is('share')",
    )),
  )
  let assert Ok(_) = done
  use done <- promise.await(browser.contains(
    browser.locator(page, ".artifact-panel"),
    "shared ↗",
  ))
  let assert Ok(_) = done
  use second_link <- promise.await(browser.attribute(
    browser.locator(page, ".artifact-share"),
    "href",
  ))
  let assert Ok(second_link) = second_link
  assert first_link != second_link
  use done <- promise.await(browser.contains(
    browser.nested_frame_locator(
      page,
      "iframe.artifact-preview",
      "iframe",
      "body",
    ),
    "Record location, time and weather.",
  ))
  let assert Ok(_) = done
  let downloading = browser.download(page)
  use done <- promise.await(
    browser.click(browser.locator(page, "button:text-is('Download workspace')")),
  )
  let assert Ok(_) = done
  use downloaded <- promise.await(downloading)
  let assert Ok(downloaded) = downloaded
  let assert Ok(cwd) = simplifile.current_directory()
  let workspace_path = filepath.join(cwd, ".recordings/artifact-workspace.json")
  use done <- promise.await(browser.save_download(downloaded, workspace_path))
  let assert Ok(_) = done
  let downloading = browser.download(page)
  use done <- promise.await(
    browser.click(browser.locator(page, ".trace-download")),
  )
  let assert Ok(_) = done
  use downloaded <- promise.await(downloading)
  let assert Ok(downloaded) = downloaded
  let output =
    otel.env_value(otel.environment(), "DEMO_OUTPUT_DIR", "recordings")
  let output = case filepath.is_absolute(output) {
    True -> output
    False -> filepath.join(cwd, output)
  }
  let archive_path = filepath.join(output, "artifact-trajectory.json")
  use done <- promise.await(browser.save_download(downloaded, archive_path))
  let assert Ok(_) = done
  let assert Ok(text) = simplifile.read(archive_path)
  let assert Ok(trace) = archive.from_string(text)
  assert archive.missing(trace) == []
  assert list.length(session.generations(trace.session)) == 4
  assert list.all(rerun.session(trace.session, trace.store), fn(report) {
    report.problem == None
  })
  use done <- promise.await(browser.goto(
    page,
    "http://127.0.0.1:5280" <> first_link,
  ))
  let assert Ok(_) = done
  use done <- promise.await(browser.contains(
    browser.locator(page, "header"),
    "newer version",
  ))
  let assert Ok(_) = done
  use done <- promise.await(browser.contains(
    browser.frame_locator(page, "iframe", "body"),
    "Revision one",
  ))
  let assert Ok(_) = done
  use done <- promise.await(
    browser.click(browser.locator(page, "a:text-is('newer version')")),
  )
  let assert Ok(_) = done
  use done <- promise.await(browser.contains(
    browser.frame_locator(page, "iframe", "body"),
    "Revision two",
  ))
  let assert Ok(_) = done
  use done <- promise.await(browser.goto(page, "http://127.0.0.1:5280/overlay/"))
  let assert Ok(_) = done
  use done <- promise.await(browser.contains(
    browser.locator(page, ".artifact-panel"),
    "v2",
  ))
  let assert Ok(_) = done
  use done <- promise.await(
    browser.click(browser.locator(page, "button[aria-label='Close notebook']")),
  )
  let assert Ok(_) = done
  use done <- promise.await(
    browser.click(browser.locator(
      page,
      "button[aria-label='History of notebook']",
    )),
  )
  let assert Ok(_) = done
  use done <- promise.await(browser.contains(
    browser.locator(page, ".artifact-inspector"),
    "v1",
  ))
  let assert Ok(_) = done
  use done <- promise.await(
    browser.click(browser.locator(page, "button:text-is('Open v1')")),
  )
  let assert Ok(_) = done
  use done <- promise.await(browser.contains(
    browser.locator(page, ".artifact-panel:has(iframe[data-version=\"1\"] )"),
    "v1",
  ))
  let assert Ok(_) = done
  use fresh <- promise.await(browser.page(browser.context_of(page)))
  let assert Ok(fresh) = fresh
  use done <- promise.await(browser.goto(
    fresh,
    "http://127.0.0.1:5280/overlay/",
  ))
  let assert Ok(_) = done
  use done <- promise.await(browser.set_input_files(
    browser.locator(fresh, "input[aria-label='Import workspace']"),
    workspace_path,
  ))
  let assert Ok(_) = done
  use done <- promise.await(browser.contains(
    browser.locator(fresh, ".artifact-panel"),
    "v2",
  ))
  let assert Ok(_) = done
  use done <- promise.await(browser.count(
    browser.locator(fresh, ".artifact-share:text-is('shared ↗')"),
    0,
  ))
  let assert Ok(_) = done
  use done <- promise.map(browser.close_page(fresh))
  let assert Ok(_) = done
}

fn prompt(page, text, answer) {
  use done <- promise.await(browser.fill(
    browser.locator(page, ".chat-input textarea"),
    text,
  ))
  let assert Ok(_) = done
  use done <- promise.await(browser.press(
    browser.locator(page, ".chat-input textarea"),
    "Enter",
  ))
  let assert Ok(_) = done
  use done <- promise.map(browser.contains(
    browser.locator(page, ".messages"),
    answer,
  ))
  let assert Ok(_) = done
}
