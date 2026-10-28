//// Evaluate the actual EYG viewer constructors, then send their bundles to web Overlay.

import eyg/hub/cache
import eyg/interpreter/cast
import eyg/interpreter/expression
import eyg/interpreter/simple_debug
import gleam/bit_array
import gleam/javascript/promise
import gleam/json
import gleam/result
import gleam/string
import loam/execute
import loam/source
import loam/system
import ogre/origin
import simplifile

pub fn quote(text) {
  json.to_string(json.string(text))
}

pub fn render(code) {
  let assert Ok(cwd) = simplifile.current_directory()
  let assert Ok(tree) = source.parse(code, source.Disk(cwd <> "/guide.eyg"))
  let effect =
    execute.pure_loop(
      expression.execute(tree, []),
      execute.State(origin.https("unused.invalid"), cache.ready()),
    )
  use rendered <- promise.map(system.run(effect))
  let assert #(Ok(bundle), _) = rendered
  let assert Ok(files) =
    cast.as_list_of(bundle, fn(raw) {
      use path <- result.try(cast.field("path", cast.as_string, raw))
      use media_type <- result.try(cast.field("media_type", cast.as_string, raw))
      use content <- result.try(cast.field("content", cast.as_binary, raw))
      let assert Ok(text) = bit_array.to_string(content)
      Ok(
        "{path: "
        <> quote(path)
        <> ", media_type: "
        <> quote(media_type)
        <> ", content: !string_to_binary("
        <> quote(text)
        <> ")}",
      )
    })
  "[" <> string.join(files, ", ") <> "]"
}

pub fn carousel() {
  render(
    "let v = import \"../../eyg_packages/artifact_viewers/carousel.eyg\" v.render({title: \"Route views\", images: [{caption: \"First\", media_type: \"image/svg+xml\", content: !string_to_binary(\"<svg xmlns='http://www.w3.org/2000/svg' width='300' height='150'><rect width='300' height='150' fill='#568275'/></svg>\")}, {caption: \"Second\", media_type: \"image/svg+xml\", content: !string_to_binary(\"<svg xmlns='http://www.w3.org/2000/svg' width='300' height='150'><rect width='300' height='150' fill='#ceac63'/></svg>\")}]})",
  )
}

pub fn video() {
  render(
    "let v = import \"../../eyg_packages/artifact_viewers/video.eyg\" v.render({title: \"Clip\", media_type: \"video/webm\", content: !string_to_binary(\"\")})",
  )
}

pub fn bluesky() {
  let feed =
    json.object([
      #(
        "feed",
        json.preprocessed_array([
          json.object([
            #(
              "post",
              json.object([
                #(
                  "author",
                  json.object([
                    #("displayName", json.string("Bus Company")),
                    #("handle", json.string("bus.example")),
                  ]),
                ),
                #(
                  "record",
                  json.object([
                    #("$type", json.string("app.bsky.feed.post")),
                    #(
                      "text",
                      json.string("</script><img src=x onerror=attack()>"),
                    ),
                    #("createdAt", json.string("2026-10-14T13:00:00Z")),
                  ]),
                ),
                #("likeCount", json.int(3)),
              ]),
            ),
          ]),
          json.object([
            #(
              "post",
              json.object([
                #(
                  "record",
                  json.object([#("$type", json.string("other.lexicon"))]),
                ),
              ]),
            ),
          ]),
        ]),
      ),
    ])
    |> json.to_string
  render(
    "let v = import \"../../eyg_packages/artifact_viewers/bluesky.eyg\" v.render({title: \"Posts\", feed: "
    <> quote(feed)
    <> ", retrieved_at: \"2026-10-14\"})",
  )
}

pub fn empty_carousel() {
  render(
    "let v = import \"../../eyg_packages/artifact_viewers/carousel.eyg\" v.render({title: \"Empty\", images: []})",
  )
}

pub fn invalid_bluesky() {
  render(
    "let v = import \"../../eyg_packages/artifact_viewers/bluesky.eyg\" v.render({title: \"Posts\", feed: \"not json\", retrieved_at: \"2026-10-14\"})",
  )
}

pub fn control_code() {
  let assert Ok(library) =
    simplifile.read("../../eyg_packages/playwright/index.eyg")
  "let library = (_) -> {"
  <> library
  <> "}\nlet pw = library({})\nlet page = pw.page(\"notebook\")\n"
  <> "let _ = pw.fill(pw.get_by_placeholder(page, \"topic\"), \"Migrating birds\")\n"
  <> "let _ = pw.expect(pw.get_by_label(page, \"Topic\")).to_have_value(\"Migrating birds\")\n"
  <> "let _ = pw.uncheck(pw.get_by_label(page, \"Reviewed\"))\n"
  <> "let _ = pw.expect(pw.get_by_label(page, \"Reviewed\")).not_to_be_checked({})\n"
  <> "let _ = pw.press(pw.get_by_label(page, \"Topic\"), \"!\")\n"
  <> "let _ = pw.expect(pw.get_by_label(page, \"Topic\")).to_have_value(\"Migrating birds!\")\n"
  <> "pw.screenshot(pw.locator(page, \"h1\"))"
}

pub fn save(name, bundle, code) {
  "let _ = perform Artifact({name: "
  <> quote(name)
  <> ", bundle: "
  <> bundle
  <> "})\n"
  <> "let _ = perform Show({item: Artifact("
  <> quote(name)
  <> "), origin: {x: 0, y: 0}, size: {x: 1000, y: 1000}})\n"
  <> code
}

pub fn library() {
  let assert Ok(source) =
    simplifile.read("../../eyg_packages/playwright/index.eyg")
  "let library = (_) -> {" <> source <> "}\nlet pw = library({})\n"
}

pub fn carousel_check() {
  library()
  <> "let page = pw.page(\"carousel\")\n"
  <> "let _ = pw.expect(pw.locator(page, \"#position\")).to_have_text(\"1 / 2\")\n"
  <> "let _ = pw.click(pw.get_by_role(page, \"button\", \"Next image\"))\n"
  <> "let _ = pw.expect(pw.locator(page, \"#position\")).to_have_text(\"2 / 2\")\n"
  <> "let _ = pw.expect(pw.first(pw.locator(page, \"figure\"))).to_be_hidden({})\n"
  <> "let _ = pw.click(pw.get_by_role(page, \"button\", \"Next image\"))\n"
  <> "let _ = pw.expect(pw.locator(page, \"#position\")).to_have_text(\"1 / 2\")\n"
  <> "let _ = pw.press(page, \"ArrowLeft\")\n"
  <> "let _ = pw.expect(pw.locator(page, \"#position\")).to_have_text(\"2 / 2\")\n"
  <> "pw.screenshot(page)"
}

pub fn bluesky_check() {
  library()
  <> "let page = pw.page(\"posts\")\n"
  <> "let _ = pw.expect(pw.locator(page, \"article\")).to_have_count(1)\n"
  <> "let _ = pw.expect(pw.locator(page, \"article\")).to_contain_text(\"Bus Company\")\n"
  <> "let _ = pw.expect(pw.locator(page, \"article p\")).to_have_text(\"</script><img src=x onerror=attack()>\")\n"
  <> "let _ = pw.expect(pw.locator(page, \"img\")).to_have_count(0)\n"
  <> "pw.screenshot(page)"
}

pub fn video_check() {
  library()
  <> "let page = pw.page(\"clip\")\n"
  <> "let _ = pw.select_option(pw.get_by_label(page, \"Playback speed\"), \"2\")\n"
  <> "let _ = pw.expect(pw.get_by_label(page, \"Playback speed\")).to_have_value(\"2\")\n"
  <> "pw.screenshot(page)"
}

pub fn isolation() {
  let assert Ok(script) =
    simplifile.read("../overlay_puppet/build/preview/isolation.js")
  let html =
    "<meta http-equiv=\"Content-Security-Policy\" content=\"default-src * 'unsafe-inline'; script-src data: 'unsafe-inline' *; connect-src *; img-src *\"><body><h1>Isolation check</h1><script src=\"check.js\"></script><link rel=\"stylesheet\" href=\"css/main.css\"></body>"
  let file = fn(path, type_, text) {
    "{path: "
    <> quote(path)
    <> ", media_type: "
    <> quote(type_)
    <> ", content: !string_to_binary("
    <> quote(text)
    <> ")}"
  }
  "["
  <> string.join(
    [
      file("index.html", "text/html", html),
      file("check.js", "text/javascript", script),
      file(
        "css/main.css",
        "text/css",
        "@import 'nested.css'; body{background:#f5f2e9}",
      ),
      file(
        "css/nested.css",
        "text/css",
        "body{color:rgb(12,34,56);font:20px system-ui}",
      ),
    ],
    ", ",
  )
  <> "]"
}

pub fn layout(kind) {
  let assert Ok(cwd) = simplifile.current_directory()
  let code =
    "let layout = import \"../../eyg_packages/tiling/"
    <> kind
    <> ".eyg\" layout.layout([Artifact(\"carousel\"), Artifact(\"posts\"), Artifact(\"notebook\")], {origin: {x: 0, y: 0}, size: {x: 1000, y: 1000}}"
    <> case kind {
      "main_stack" -> ", 600"
      _ -> ""
    }
    <> ")"
  let assert Ok(tree) = source.parse(code, source.Disk(cwd <> "/guide.eyg"))
  use rendered <- promise.map(
    system.run(execute.pure_loop(
      expression.execute(tree, []),
      execute.State(origin.https("unused.invalid"), cache.ready()),
    )),
  )
  let assert #(Ok(placements), _) = rendered
  "!list_fold("
  <> simple_debug.inspect(placements)
  <> ", {}, (placement, _) -> { match perform Show(placement) { Ok(_) -> { {} } Error(reason) -> { !never(perform Abort(reason)) } } })"
}
