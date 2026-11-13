//// Browser regression for the running howdy/Lustre example chat.
//// Set EXAMPLE_CHAT_ORIGIN to an isolated chat instance before running.

import gleam/io
import gleam/javascript/promise
import gleam_playwright as browser
import otel
import simplifile

pub fn main() {
  let env = otel.environment()
  let origin =
    otel.env_value(env, "EXAMPLE_CHAT_ORIGIN", "http://localhost:8188")
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
  use checked <- promise.await(walkthrough(page, origin))
  use _ <- promise.await(browser.screenshot(
    page,
    ".recordings/example-chat.png",
  ))
  use _ <- promise.await(browser.close_context(context))
  use _ <- promise.map(browser.close_browser(launched))
  assert checked == Ok(Nil) as "example chat browser regression"
  io.println(
    "PASS example chat: keyboard composition, threads, reactions and channel switching",
  )
}

fn walkthrough(page, origin) {
  use _ <- promise.try_await(browser.goto(
    page,
    origin <> "/?name=browser-review&channel=general",
  ))
  use _ <- promise.try_await(browser.contains(
    browser.locator(page, "#title"),
    "# general",
  ))
  use _ <- promise.try_await(browser.fill(
    browser.locator(page, "#text"),
    "Browser regression message",
  ))
  use _ <- promise.try_await(browser.press(
    browser.locator(page, "#text"),
    "Enter",
  ))
  use _ <- promise.try_await(browser.contains(
    browser.locator(page, "#messages"),
    "Browser regression message",
  ))
  use _ <- promise.try_await(browser.count(
    browser.locator(page, "#messages .message"),
    1,
  ))
  use _ <- promise.try_await(
    browser.hover(browser.locator(page, "#messages .message")),
  )
  use _ <- promise.try_await(
    browser.click(browser.locator(page, "#messages button[title='React books']")),
  )
  use _ <- promise.try_await(browser.contains(
    browser.locator(page, "#messages .reaction"),
    "📚 1",
  ))
  use _ <- promise.try_await(
    browser.click(browser.locator(
      page,
      "#messages button[title='Reply in thread']",
    )),
  )
  use _ <- promise.try_await(browser.fill(
    browser.locator(page, "#reply-text"),
    "A reply",
  ))
  use _ <- promise.try_await(
    browser.click(browser.locator(page, "#reply .send")),
  )
  use _ <- promise.try_await(browser.contains(
    browser.locator(page, "#replies"),
    "A reply",
  ))
  use _ <- promise.try_await(browser.count(
    browser.locator(page, "#replies .message"),
    2,
  ))
  use _ <- promise.try_await(
    browser.click(browser.locator(page, "#channels button:has-text('# random')")),
  )
  use _ <- promise.try_await(browser.count(browser.locator(page, "#thread"), 0))
  use _ <- promise.try_await(browser.contains(
    browser.locator(page, "#title"),
    "# random",
  ))
  use _ <- promise.try_await(browser.fill(
    browser.locator(page, "#text"),
    "First line",
  ))
  use _ <- promise.try_await(browser.press(
    browser.locator(page, "#text"),
    "Shift+Enter",
  ))
  use _ <- promise.try_await(browser.press(
    browser.locator(page, "#text"),
    "End",
  ))
  use _ <- promise.try_await(
    browser.click(browser.locator(page, "#compose .send")),
  )
  use _ <- promise.try_await(browser.contains(
    browser.locator(page, "#messages"),
    "First line",
  ))
  browser.count(browser.locator(page, "#messages .message"), 1)
}
