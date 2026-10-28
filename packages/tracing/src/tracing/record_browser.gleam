//// Shared recording/cleanup for guide walkthroughs, including failure diagnostics.

import filepath
import gleam/dynamic/decode
import gleam/int
import gleam/javascript/promise
import gleam/result
import gleam/string
import gleam_playwright as browser
import otel
import simplifile

pub fn run(name, steps) {
  let env = otel.environment()
  let output = otel.env_value(env, "DEMO_OUTPUT_DIR", "recordings")
  let assert Ok(_) = simplifile.create_directory_all(output)
  let assert Ok(_) = simplifile.create_directory_all(".recordings")
  use launched <- promise.await(browser.launch(
    otel.env_value(env, "CHROME_BIN", ""),
    250,
  ))
  let launched = case launched {
    Ok(value) -> value
    Error(reason) -> panic as reason
  }
  use context <- promise.await(browser.context(
    launched,
    ".recordings",
    1280,
    800,
  ))
  let context = case context {
    Ok(value) -> value
    Error(reason) -> panic as reason
  }
  use page <- promise.await(browser.page(context))
  let page = case page {
    Ok(value) -> value
    Error(reason) -> panic as reason
  }
  let video = browser.video(page)
  let outcome = steps(page) |> promise.map(Ok) |> promise.rescue(Error)
  use outcome <- promise.await(outcome)
  use html <- promise.await(browser.content(page))
  let assert Ok(_) = simplifile.write(".recordings/" <> name <> ".html", html)
  let path = case outcome {
    Ok(_) -> filepath.join(output, name)
    Error(_) -> ".recordings/" <> name <> "-failed"
  }
  use _ <- promise.await(browser.screenshot(page, path <> ".png"))
  use _ <- promise.await(browser.close_context(context))
  use _ <- promise.await(browser.save_video(video, path <> ".webm"))
  use _ <- promise.map(browser.close_browser(launched))
  case outcome {
    Ok(_) -> Nil
    Error(reason) -> panic as failure(reason)
  }
}

fn failure(reason) {
  let location = {
    use file <- decode.optional_field("file", "", decode.string)
    use line <- decode.optional_field("line", 0, decode.int)
    use message <- decode.optional_field("message", "", decode.string)
    decode.success(#(file, line, message))
  }
  let value = decode.field("value", decode.dynamic, decode.success)
  let details =
    decode.run(reason, value)
    |> result.map(string.inspect)
    |> result.unwrap(string.inspect(reason))
  case decode.run(reason, location) {
    Ok(#(file, line, message)) ->
      file <> ":" <> int.to_string(line) <> ": " <> message <> " " <> details
    Error(_) -> details
  }
}
