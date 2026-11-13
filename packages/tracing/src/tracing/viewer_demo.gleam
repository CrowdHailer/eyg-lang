//// Check EYG content-addressable viewer implementations in real sandboxed previews.

import gleam/io
import gleam/javascript/promise
import gleam/list
import gleam_playwright as browser
import javascript/mutable_reference as ref
import plinthx/browser/node as dom
import plinthx/bun/server
import tracing/artifact_fixture
import tracing/record_browser
import tracing/viewer_fixture as viewer

pub fn main() {
  use carousel <- promise.await(viewer.carousel())
  use posts <- promise.await(viewer.bluesky())
  use video <- promise.await(viewer.video())
  use empty <- promise.await(viewer.empty_carousel())
  use invalid <- promise.await(viewer.invalid_bluesky())
  use dwindle <- promise.await(viewer.layout("dwindle"))
  use main_stack <- promise.await(viewer.layout("main_stack"))
  let codes = [
    #("Isolation", viewer.save("isolation", viewer.isolation(), "{}")),
    #("Dwindle", dwindle),
    #("Main and stack", main_stack),
    #("Carousel", viewer.save("carousel", carousel, viewer.carousel_check())),
    #("Posts", viewer.save("posts", posts, viewer.bluesky_check())),
    #("Video", viewer.save("clip", video, viewer.video_check())),
    #("Empty", viewer.save("empty", empty, "{}")),
    #("Invalid", viewer.save("invalid", invalid, "{}")),
    #("Notebook", artifact_fixture.code(False)),
    #("Control", viewer.control_code()),
  ]
  let assert Ok(fixture) = artifact_fixture.start_with(codes)
  let outcome =
    record_browser.run("artifact-viewers", walkthrough)
    |> promise.map(Ok)
    |> promise.rescue(Error)
  use outcome <- promise.await(outcome)
  use stopped <- promise.map(server.stop(fixture, True))
  let assert Ok(_) = stopped
  let assert Ok(_) = outcome
  io.println(
    "PASS EYG artifact guide: isolation, carousel, media controls, literal feed text, error states, Playwright actions and both tiling layouts",
  )
}

fn walkthrough(page) {
  browser.on_error(page, io.print_error)
  let leaks = ref.new([])
  // Routing observes attempted network I/O; browser request events also include CSP failures.
  use routed <- promise.await(
    browser.route(page, "**/artifact-leak?*", fn(route) {
      let _ = ref.set(leaks, [browser.route_url(route), ..ref.get(leaks)])
      use done <- promise.map(browser.fulfill(route, 204, ""))
      let assert Ok(_) = done
      Nil
    }),
  )
  let assert Ok(_) = routed
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
  use _ <- promise.await(prompt(page, "Isolation", 0))
  use checked <- promise.await(
    promise.await_list(
      list.map(
        [
          "executed",
          "cookie",
          "local",
          "session",
          "indexed",
          "parent",
          "top",
          "fetch",
        ],
        fn(name) {
          let value = case name {
            "executed" -> "yes"
            _ -> "blocked"
          }
          browser.has_attribute(
            frame(page, "isolation", "body"),
            "data-" <> name,
            value,
          )
        },
      ),
    ),
  )
  let assert [] = list.filter(checked, fn(result) { result != Ok(Nil) })
  use _ <- promise.await(dom.sleep(250))
  let assert [] = ref.get(leaks)
  use _ <- promise.await(close(page, "isolation"))
  use _ <- promise.await(prompt(page, "Carousel", 1))
  use done <- promise.await(browser.contains(
    frame(page, "carousel", "#position"),
    "2 / 2",
  ))
  let assert Ok(_) = done
  use _ <- promise.await(close(page, "carousel"))
  use _ <- promise.await(prompt(page, "Posts", 2))
  use done <- promise.await(browser.count(frame(page, "posts", "article"), 1))
  let assert Ok(_) = done
  use done <- promise.await(browser.count(frame(page, "posts", "img"), 0))
  let assert Ok(_) = done
  use _ <- promise.await(close(page, "posts"))
  use _ <- promise.await(prompt(page, "Video", 3))
  use value <- promise.await(browser.numeric_property(
    frame(page, "clip", "video"),
    "playbackRate",
  ))
  let assert Ok(2.0) = value
  use _ <- promise.await(close(page, "clip"))
  use _ <- promise.await(prompt(page, "Empty", 3))
  use done <- promise.await(browser.contains(
    frame(page, "empty", "#empty"),
    "No images supplied.",
  ))
  let assert Ok(_) = done
  use _ <- promise.await(close(page, "empty"))
  use _ <- promise.await(prompt(page, "Invalid", 3))
  use done <- promise.await(browser.contains(
    frame(page, "invalid", "#posts"),
    "Unable to display feed",
  ))
  let assert Ok(_) = done
  use _ <- promise.await(close(page, "invalid"))
  use _ <- promise.await(prompt(page, "Notebook", 4))
  use _ <- promise.await(prompt(page, "Control", 5))
  use value <- promise.await(browser.attribute(
    frame(page, "notebook", "#topic"),
    "id",
  ))
  let assert Ok("topic") = value
  use _ <- promise.await(prompt(page, "Dwindle", 5))
  use done <- promise.await(browser.count(
    browser.locator(page, ".artifact-panel"),
    3,
  ))
  let assert Ok(_) = done
  use done <- promise.await(browser.has_attribute(
    browser.locator(
      page,
      ".artifact-panel:has(iframe[data-artifact='carousel'])",
    ),
    "style",
    "left:0.0%;top:0.0%;width:50.0%;height:100.0%",
  ))
  let assert Ok(_) = done
  use _ <- promise.await(prompt(page, "Main and stack", 5))
  use done <- promise.map(browser.has_attribute(
    browser.locator(
      page,
      ".artifact-panel:has(iframe[data-artifact='carousel'])",
    ),
    "style",
    "left:0.0%;top:0.0%;width:60.0%;height:100.0%",
  ))
  let assert Ok(_) = done
}

fn prompt(page, prompt, images) {
  use done <- promise.await(browser.fill(
    browser.locator(page, ".chat-input textarea"),
    prompt,
  ))
  let assert Ok(_) = done
  use done <- promise.await(browser.press(
    browser.locator(page, ".chat-input textarea"),
    "Enter",
  ))
  let assert Ok(_) = done
  use done <- promise.await(browser.contains(
    browser.locator(page, ".messages"),
    "Checked " <> prompt <> ".",
  ))
  let assert Ok(_) = done
  use done <- promise.map(browser.count(
    browser.locator(page, ".tool-images img"),
    images,
  ))
  let assert Ok(_) = done
}

fn frame(page, name, selector) {
  browser.nested_frame_locator(
    page,
    "iframe.artifact-preview[data-artifact='" <> name <> "']",
    "iframe",
    selector,
  )
}

fn close(page, name) {
  use done <- promise.map(
    browser.click(browser.locator(
      page,
      "button[aria-label='Close " <> name <> "']",
    )),
  )
  let assert Ok(_) = done
}
