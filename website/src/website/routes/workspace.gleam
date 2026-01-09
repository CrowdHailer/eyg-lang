import eyg/ir/dag_json
import gleam/javascript/array
import gleam/javascript/promise
import gleam/list
import gleam/option.{Some}
import gleam/string
import lustre
import lustre/attribute as a
import lustre/effect
import lustre/element
import lustre/element/html as h
import midas/browser
import morph/editable
import morph/projection
import mysig/asset
import mysig/html
import plinth/browser/clipboard
import plinth/browser/document
import plinth/browser/event
import plinth/browser/file
import plinth/browser/file_system
import plinth/browser/message_event
import plinth/browser/window
import plinth/browser/window_proxy
import spotless
import website/config
import website/harness/browser/alert
import website/harness/browser/copy
import website/harness/browser/download
import website/harness/browser/fetch
import website/harness/browser/follow
import website/harness/browser/geolocation
import website/harness/browser/now
import website/harness/browser/paste
import website/harness/browser/prompt
import website/harness/browser/random
import website/routes/common
import website/routes/home
import website/routes/workspace/state
import website/routes/workspace/view
import website/sync/client

pub fn app(module, func) {
  use script <- asset.do(asset.bundle(module, func))
  layout([
    h.div(
      [a.id("app"), a.styles([#("position", "absolute"), #("inset", "0")])],
      [],
    ),
    h.script([a.src(asset.src(script))], ""),
  ])
}

fn layout(body) {
  use layout <- asset.do(asset.load(home.layout_path))
  use neo <- asset.do(asset.load("src/website/routes/neo.css"))
  html.doc(
    list.flatten([
      [
        html.stylesheet(html.tailwind_2_2_11),
        html.stylesheet(asset.src(layout)),
        html.stylesheet(asset.src(neo)),
        common.prism_style(),
        h.style([], "html { height: 100%; }\nbody { min-height: 100%; }\n"),
      ],
      common.page_meta(
        "/",
        "EYG",
        "EYG is a programming language for predictable, useful and most of all confident development.",
      ),
      common.diagnostics(),
    ]),
    body,
  )
  |> asset.done()
}

pub fn page() {
  use content <- asset.do(app("website/routes/workspace", "client"))
  asset.done(element.to_document_string(content))
}

pub fn client() {
  let app = lustre.application(do_init, do_update, view.render)
  let assert Ok(runtime) = lustre.start(app, "#app", config.load())
  window.on_message(window.self(), fn(event) {
    let message = lustre.dispatch(state.WindowReceivedMessageEvent(event:))
    lustre.send(runtime, message)
    Nil
  })
  // Cant get persisted directory unless from a keypress
  // promise.map(get_persisted_directory(), fn(result) {
  //   case result {
  //     Ok(handle) -> {
  //       let message =
  //         lustre.dispatch(state.ShowDirectoryPickerCompleted(Ok(handle)))
  //       lustre.send(runtime, message)
  //     }
  //     Error(_) -> Nil
  //   }
  // })
  document.add_event_listener("keydown", fn(e) {
    let message = lustre.dispatch(state.UserPressedCommandKey(event.key(e)))
    lustre.send(runtime, message)
  })
  Nil
}

fn do_init(config) {
  let #(state, actions) = state.init(config)
  #(state, effect.batch(list.map(actions, run)))
}

fn do_update(state, message) {
  let #(state, actions) = state.update(state, message)
  #(state, effect.batch(list.map(actions, run)))
}

fn run(action) {
  case action {
    state.FocusOnInput -> {
      // This seems to be unnecessary if only one autofocused input, and the code doesn't have a tabindex
      effect.none()
    }
    state.WriteToClipboard(text:) ->
      effect.from(fn(dispatch) {
        promise.map(clipboard.write_text(text), fn(result) {
          dispatch(state.ClipboardWriteCompleted(result))
        })
        Nil
      })
    state.ReadFromClipboard ->
      effect.from(fn(dispatch) {
        promise.map(clipboard.read_text(), fn(result) {
          dispatch(state.ClipboardReadCompleted(result))
        })
        Nil
      })
    state.RunEffect(reference, effect) ->
      effect.from(fn(dispatch) {
        promise.map(run_effect(effect), fn(result) {
          dispatch(state.EffectImplementationCompleted(reference, result))
        })
        Nil
      })
    state.SyncAction(action) ->
      client.lustre_run_single(action, state.SyncMessage)
    state.ShowDirectoryPicker -> {
      effect.from(fn(dispatch) {
        promise.map(show_save_directory_picker(), fn(result) {
          dispatch(state.ShowDirectoryPickerCompleted(result))
        })
        Nil
      })
    }
    state.LoadFiles(handle:) -> {
      effect.from(fn(dispatch) {
        {
          use #(_, files) <- promise.try_await(file_system.all_entries(handle))
          use results <- promise.await(
            promise.await_list(
              list.map(array.to_list(files), fn(entry) {
                let name = file_system.name(entry)
                let filename = case string.split_once(name, ".eyg.json") {
                  Ok(#(name, "")) -> #(name, state.EygJson)
                  _ -> todo
                }

                use file <- promise.await(file_system.get_file(entry))
                let assert Ok(file) = file
                use b <- promise.await(file.bytes(file))

                promise.resolve(#(filename, dag_json.from_block(b)))
              }),
            ),
          )
          promise.resolve(Ok(results))
        }
        |> promise.map(fn(results) { dispatch(state.LoadedFiles(results)) })
        Nil
      })
    }
    state.SetFlushTimer(reference) ->
      effect.from(fn(dispatch) {
        promise.map(promise.wait(2000), fn(_: Nil) {
          dispatch(state.FlushTimeout(reference:))
        })
        Nil
      })
    state.SaveFile(handle:, filename:, projection:) -> {
      effect.from(fn(_dispatch) {
        {
          let name = case filename.1 {
            state.EygJson -> filename.0 <> ".eyg.json"
          }
          use file_handle <- promise.try_await(file_system.get_file_handle(
            handle,
            name,
            True,
          ))

          use writable <- promise.try_await(file_system.create_writable(
            file_handle,
          ))
          let content =
            projection.rebuild(projection)
            |> editable.to_annotated([])
            |> dag_json.to_block()

          use Nil <- promise.try_await(file_system.write(writable, content))
          use Nil <- promise.try_await(file_system.close(writable))
          promise.resolve(Ok(Nil))
        }
        |> promise.map(fn(r) { echo r })
        Nil
      })
    }
    state.SpotlessConnect(effect_counter:, origin:, service:) -> {
      let assert Some(port) = origin.port
      effect.from(fn(dispatch) {
        promise.map(browser.run_task(spotless.dnsimple(port)), fn(result) {
          dispatch(state.SpotlessConnected(
            reference: effect_counter,
            service:,
            result:,
          ))
        })
        Nil
      })
    }
    state.OpenPopup(location) -> {
      effect.from(fn(dispatch) {
        dispatch(state.OpenPopupCompleted(browser.open(location, #(650, 800))))
        Nil
      })
    }
    state.PostMessage(target:, payload:) ->
      effect.from(fn(_dispatch) {
        window_proxy.post_message(target, payload, "*")
        Nil
      })
  }
}

fn run_effect(effect) {
  case effect {
    state.Alert(message) -> alert.run(message)
    state.Copy(text) -> copy.run(text)
    state.Download(file) -> download.run(file)
    state.Fetch(request) -> fetch.run(request)
    state.Follow(request) -> follow.run(request)
    state.Geolocation -> geolocation.run()
    state.Now -> now.run()
    state.Paste -> paste.run()
    state.Prompt(message) -> prompt.run(message)
    state.Random(max) -> random.run(max)
  }
}

@external(javascript, "../../website_ffi.mjs", "show_save_directory_picker")
fn show_save_directory_picker() -> promise.Promise(
  Result(file_system.Handle(file_system.D), String),
)

@external(javascript, "../../website_ffi.mjs", "get_persisted_directory")
fn get_persisted_directory() -> promise.Promise(
  Result(file_system.Handle(file_system.D), String),
)
