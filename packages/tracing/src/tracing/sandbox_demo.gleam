//// Record the checked sealed cohort in the browser debugger.

import gleam/io
import gleam/javascript/promise
import gleam_playwright as browser
import plinthx/bun/server
import tracing/model_fixture
import tracing/record_browser

pub fn main() {
  let assert Ok(fixture) = model_fixture.start()
  let outcome =
    record_browser.run("sandbox", walkthrough)
    |> promise.map(Ok)
    |> promise.rescue(Error)
  use outcome <- promise.await(outcome)
  use stopped <- promise.map(server.stop(fixture, True))
  let assert Ok(_) = stopped
  let assert Ok(_) = outcome
  io.println(
    "PASS browser sandbox guide: report diff, replay, cached variant and refused host",
  )
}

fn walkthrough(page) {
  use done <- promise.await(browser.goto(
    page,
    "http://127.0.0.1:7201/glasshouse/debugger/?demo=sandbox",
  ))
  let assert Ok(_) = done
  use done <- promise.await(browser.contains(
    browser.locator(page, ".gh-traces"),
    "Sealed session",
  ))
  let assert Ok(_) = done
  use done <- promise.await(
    browser.click(browser.locator(
      page,
      ".gh-timeline button:has-text('WriteFile')",
    )),
  )
  let assert Ok(_) = done
  use done <- promise.await(browser.contains(
    browser.locator(page, ".gh-detail"),
    "signups.md",
  ))
  let assert Ok(_) = done
  use done <- promise.await(
    browser.click(browser.locator(page, "button:text-is('Replay')")),
  )
  let assert Ok(_) = done
  use done <- promise.await(
    browser.click(browser.locator(
      page,
      "button:text-is('Replay Sealed session')",
    )),
  )
  let assert Ok(_) = done
  use done <- promise.await(browser.contains(
    browser.locator(page, ".gh-replay-summary"),
    "2 runs reproduced exactly",
  ))
  let assert Ok(_) = done
  use done <- promise.await(
    browser.click(browser.locator(page, "button:text-is('Unchanged fork')")),
  )
  let assert Ok(_) = done
  use done <- promise.await(browser.contains(
    browser.locator(page, ".gh-meta"),
    "replayed",
  ))
  let assert Ok(_) = done
  use done <- promise.await(
    browser.click(browser.locator(page, "button:text-is('Refused host')")),
  )
  let assert Ok(_) = done
  use done <- promise.await(
    browser.click(browser.locator(page, "button:text-is('Compare variants')")),
  )
  let assert Ok(_) = done
  use done <- promise.map(browser.contains(
    browser.locator(page, ".gh-detail"),
    "Changed skill",
  ))
  let assert Ok(_) = done
  use done <- promise.map(browser.contains(
    browser.locator(page, ".gh-detail"),
    "not permitted",
  ))
  let assert Ok(_) = done
}
