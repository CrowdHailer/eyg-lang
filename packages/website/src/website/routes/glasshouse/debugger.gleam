//// The time travel debugger, a client side app for recorded sessions.

import gleam/dynamic/decode
import gleam/option.{None}
import gleam/result
import gleam/string
import plinth/browser/document
import plinth/browser/element as dom
import plinth/browser/event as native_event
import plinth/browser/location
import plinth/browser/window
import plinthx/browser/element as extra_element
import plinthx/browser/event as extra_event
import plinthx/browser/fetch
import plinthx/browser/url

import gleam/int
import gleam/javascript/promise.{type Promise}
import gleam/list
import lustre
import lustre/attribute as a
import lustre/effect
import lustre/element
import lustre/element/html as h
import mysig/asset
import plinth/browser/file
import website/routes/glasshouse/debugger/state
import website/routes/glasshouse/debugger/view
import website/routes/glasshouse/layout

pub fn page() {
  use script <- asset.do(asset.bundle(
    "website/routes/glasshouse/debugger",
    "client",
  ))
  let #(initial, _) = state.init("")
  use content <- asset.do(
    layout.page(
      "/glasshouse/debugger",
      "Glasshouse debugger",
      "Step through a recorded EYG agent session, its effects, files and generations, and compare evaluated variants.",
      [],
      [
        h.div([a.id("app")], [view.view(initial)]),
        h.script([a.src(asset.src(script))], ""),
      ],
    ),
  )
  asset.done(element.to_document_string(content))
}

// client has to be a top level function for bundling
pub fn client() {
  let app = lustre.application(init, update, view.view)
  let assert Ok(runtime) = lustre.start(app, "#app", search())
  on_key(fn(key) {
    lustre.send(runtime, lustre.dispatch(state.UserPressedKey(key)))
  })
  Nil
}

fn init(query) {
  let #(model, actions) = state.init(query)
  #(model, effect.batch(list.map(actions, run)))
}

fn update(model: state.Model, message) {
  let previous = model.moment
  let #(model, actions) = state.update(model, message)
  let scroll = case model.moment == previous {
    True -> effect.none()
    False -> {
      let id = "moment-" <> int.to_string(model.moment)
      effect.after_paint(fn(_, _) { scroll_into_view(id) })
    }
  }
  #(model, effect.batch([scroll, ..list.map(actions, run)]))
}

fn run(action) {
  case action {
    state.FetchArchive(demo) ->
      from_promise(fetch_text(state.demo_path(demo)), state.ArchiveFetched(
        demo,
        _,
      ))
    state.ReadUpload(chosen) ->
      from_promise(promise.map(file.text(chosen), Ok), state.ArchiveUploaded(
        file.name(chosen),
        _,
      ))
    state.DownloadArchive(name, text) ->
      effect.from(fn(_) { download(name, text) })
  }
}

fn from_promise(task: Promise(a), message: fn(a) -> msg) {
  effect.from(fn(dispatch) {
    promise.map(task, fn(result) { dispatch(message(result)) })
    Nil
  })
}

fn fetch_text(path: String) -> Promise(Result(String, String)) {
  let assert Ok(client) = fetch.get()
  use response <- promise.await(fetch.send(
    client,
    path,
    fetch.RequestInit("GET", [], "", None),
  ))
  case response {
    Error(reason) -> promise.resolve(Error(reason))
    Ok(response) ->
      case fetch.status(response) >= 200 && fetch.status(response) < 300 {
        True -> fetch.text(response)
        False ->
          promise.resolve(Error(
            path <> " responded " <> int.to_string(fetch.status(response)),
          ))
      }
  }
}

fn download(name: String, text: String) -> Nil {
  let url = file.new(<<text:utf8>>, name) |> file.create_object_url
  let link = document.create_element("a")
  dom.set_attribute(link, "href", url)
  dom.set_attribute(link, "download", name)
  extra_element.click(link)
  url.revoke_object_url(url)
}

fn search() -> String {
  let query =
    window.self() |> window.location |> location.search |> result.unwrap("")
  case string.starts_with(query, "?") {
    True -> string.drop_start(query, 1)
    False -> query
  }
}

fn on_key(handler: fn(String) -> Nil) -> Nil {
  document.add_event_listener("keydown", fn(event) {
    let assert Ok(event) = extra_event.keyboard_event(event)
    let tag =
      decode.run(
        native_event.target(event),
        decode.field("tagName", decode.string, decode.success),
      )
      |> result.unwrap("")
    case
      tag == "INPUT"
      || tag == "TEXTAREA"
      || native_event.meta_key(event)
      || native_event.ctrl_key(event)
    {
      True -> Nil
      False -> {
        let key = native_event.key(event)
        case
          list.contains(
            ["ArrowLeft", "ArrowRight", "ArrowUp", "ArrowDown"],
            key,
          )
        {
          True -> native_event.prevent_default(event)
          False -> Nil
        }
        handler(key)
      }
    }
  })
}

fn scroll_into_view(id: String) -> Nil {
  case document.get_element_by_id(id) {
    Ok(element) -> extra_element.scroll_nearest(element)
    Error(_) -> Nil
  }
}
