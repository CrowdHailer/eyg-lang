//// Serve the real bundles to Chromium and check the browser host's assertions.

import gleam/dict
import gleam/int
import gleam/io
import gleam/javascript/promise
import gleam/list
import gleam/result
import gleam/string
import gleam_playwright as browser
import javascript/mutable_reference as reference
import plinthx/browser/fetch
import plinthx/bun/runtime
import plinthx/bun/server
import plinthx/node/process
import simplifile

pub fn main() {
  let assert Ok(bun) = runtime.get()
  let assert Ok(response_type) = fetch.get_response()
  let assert Ok(sdk) = simplifile.read("dist/eyg.mjs")
  let assert Ok(client) = simplifile.read("dist/browser_client.mjs")
  let hub_requests = reference.new(0)
  let assert Ok(fixture) =
    server.serve(
      bun,
      server.Options(0, "127.0.0.1", fn(request) {
        let url = fetch.request_url(request)
        case
          string.contains(url, "/packages/")
          || string.contains(url, "/modules/")
        {
          True -> reference.set(hub_requests, reference.get(hub_requests) + 1)
          False -> 0
        }
        let #(body, content_type) = case
          string.ends_with(url, "/eyg.mjs"),
          string.ends_with(url, "/browser_client.mjs")
        {
          True, _ -> #(sdk, "text/javascript")
          _, True -> #(client, "text/javascript")
          _, _ -> #(
            "<!doctype html><meta charset=utf-8><title>EYG native bundle check</title><pre id=result>Running...</pre><script type=module>import {main} from '/browser_client.mjs'; main();</script>",
            "text/html",
          )
        }
        use _ <- promise.map(promise.resolve(Nil))
        let assert Ok(response) =
          fetch.new_response(response_type, body, 200, [
            #("content-type", content_type),
          ])
        response
      }),
    )
  let work =
    check_browser("http://127.0.0.1:" <> int.to_string(server.port(fixture)))
    |> promise.map(Ok)
    |> promise.rescue(Error)
  use work <- promise.await(work)
  use stopped <- promise.map(server.stop(fixture, True))
  assert stopped == Ok(Nil)
  let assert Ok(_) = work
  assert reference.get(hub_requests) == 0
  io.println(
    "PASS Chromium loaded the real native bundle and retained its typed shell",
  )
}

fn check_browser(url) {
  let assert Ok(host) = process.get()
  let executable =
    process.env(host)
    |> dict.from_list
    |> dict.get("CHROME_BIN")
    |> result.unwrap("")
  let assert Ok(_) = simplifile.create_directory_all("build/browser-check")
  use launched <- promise.await(browser.launch(executable, 0))
  let assert Ok(launched) = launched
  let work =
    {
      use context <- promise.await(browser.context(
        launched,
        "build/browser-check",
        1000,
        600,
      ))
      let assert Ok(context) = context
      use page <- promise.await(browser.page(context))
      let assert Ok(page) = page
      let errors = reference.new([])
      browser.on_error(page, fn(error) {
        reference.set(errors, [error, ..reference.get(errors)])
        Nil
      })
      use opened <- promise.await(browser.goto(page, url))
      let assert Ok(_) = opened
      use checked <- promise.await(browser.contains(
        browser.locator(page, "#result"),
        "PASS native bundle: async host counter=5; retained n+1=6",
      ))
      let assert Ok(_) = checked
      assert list.is_empty(reference.get(errors))
      use captured <- promise.await(browser.screenshot(
        page,
        "build/browser-check/checked.png",
      ))
      let assert Ok(_) = captured
      use _ <- promise.map(browser.close_context(context))
      Nil
    }
    |> promise.map(Ok)
    |> promise.rescue(Error)
  use work <- promise.await(work)
  use _ <- promise.map(browser.close_browser(launched))
  let assert Ok(_) = work
}
