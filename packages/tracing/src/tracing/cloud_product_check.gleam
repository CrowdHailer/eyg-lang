//// Check the actual browser-generated EYG in every quick-trigger card.

import gleam/int
import gleam/io
import gleam/javascript/promise
import gleam/list
import gleam/option.{Some}
import gleam/uri
import gleam_playwright as browser
import loam/source
import otel
import simplifile

pub fn main() {
  let env = otel.environment()
  let assert Ok(_) = simplifile.create_directory_all(".recordings")
  use launched <- promise.await(browser.launch(
    otel.env_value(env, "CHROME_BIN", ""),
    0,
  ))
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
  browser.on_error(page, io.println_error)
  use _ <- promise.await(browser.goto(
    page,
    otel.env_value(env, "CLOUD_PRODUCT_URL", "http://localhost:8081"),
  ))
  use counted <- promise.await(browser.count(
    browser.locator(page, "#widgets .card"),
    7,
  ))
  use checked <- promise.await(check_cards(page, 1))
  use _ <- promise.await(browser.screenshot(
    page,
    ".recordings/cloud-product.png",
  ))
  use _ <- promise.await(browser.close_context(context))
  use _ <- promise.map(browser.close_browser(launched))
  assert counted == Ok(Nil)
  assert checked == Ok(Nil)
  io.println(
    "PASS quick triggers: seven cards render and generate parseable EYG",
  )
}

fn check_cards(page, index) {
  case index > 7 {
    True -> promise.resolve(Ok(Nil))
    False -> {
      let selector =
        "#widgets .card:nth-child(" <> int.to_string(index) <> ") a.button"
      use href <- promise.try_await(browser.attribute(
        browser.locator(page, selector),
        "href",
      ))
      let assert Ok(url) = uri.parse(href)
      let assert Some(query) = url.query
      let assert Ok(params) = uri.parse_query(query)
      let assert Ok(code) = list.key_find(params, "code")
      let assert Ok(_) = source.parse_input(code, source.Code(code))
      let assert Ok(_) =
        simplifile.write(
          ".recordings/quick-trigger-" <> int.to_string(index) <> ".eyg",
          code,
        )
      check_cards(page, index + 1)
    }
  }
}
