//// Browser is the API to the platform
//// It might make sense to implement a version of the effect interface built on this

import gleam/javascript/promise
import gleam/json.{type Json}
import midas/browser
import plinth/browser/clipboard
import plinth/browser/file_system
import plinth/browser/window_proxy

/// The browser platform effect
///
/// - `FocusOnInput` focus on the first input on the page.
///   This seems to be unnecessary if only one autofocused input, and the code doesn't have a tabindex
pub type Effect(m) {
  // FocusOnInput(resume:)
  LoadFiles(handle: file_system.DirectoryHandle)
  OpenPopup(
    location: String,
    resume: fn(Result(window_proxy.WindowProxy, String)) -> m,
  )
  PostMessage(
    target: window_proxy.WindowProxy,
    payload: Json,
    resume: fn(Nil) -> m,
  )
  ReadFromClipboard(resume: fn(Result(String, String)) -> m)
  SaveFile(
    handle: file_system.DirectoryHandle,
    filename: String,
    content: BitArray,
    resume: fn(Result(Nil, String)) -> m,
  )
  ShowDirectoryPicker(
    resume: fn(Result(file_system.Handle(file_system.D), String)) -> m,
  )
  WriteToClipboard(text: String, resume: fn(Result(Nil, String)) -> m)
}

// helpers like save_buffer

// pub type Action {

//   RunEffect(reference: Int, effect: Effect)
//   SyncAction(client.Action)
//   SetFlushTimer(reference: Int)
//   SpotlessConnect(
//     effect_counter: Int,
//     origin: origin.Origin,
//     service: harness.Service,
//   )
// }
//     state.OpenPopup(location) -> {
//       effect.from(fn(dispatch) {
//         dispatch(state.OpenPopupCompleted())
//         Nil
//       })
//     }

// Use an ignore event if we don't want a message
pub fn run(effect: Effect(m)) -> promise.Promise(m) {
  case effect {
    LoadFiles(handle:) -> {
      todo as "this shouldn't read every file"
      // use #(_, files) <- promise.await(file_system.all_entries(handle))
      // use results <- promise.await(
      //   promise.await_list(
      //     list.filter_map(array.to_list(files), fn(entry) {
      //       let name = file_system.name(entry)
      //       use filename <- result.map(
      //         case string.split_once(name, ".eyg.json") {
      //           Ok(#(name, "")) -> Ok(#(name, state.EygJson))
      //           _ -> Error(Nil)
      //         },
      //       )

      //       use file <- promise.await(file_system.get_file(entry))
      //       let assert Ok(file) = file
      //       use b <- promise.await(file.bytes(file))

      //       promise.resolve(#(filename, dag_json.from_block(b)))
      //     }),
      //   ),
      // )
      // promise.resolve(Ok(results))
      // todo
    }
    OpenPopup(location:, resume:) -> {
      promise.resolve(resume(browser.open(location, #(650, 800))))
    }
    PostMessage(target:, payload:, resume:) ->
      promise.resolve(resume(window_proxy.post_message(target, payload, "*")))
    ReadFromClipboard(resume) -> {
      use result <- promise.map(clipboard.read_text())
      resume(result)
    }
    SaveFile(handle:, filename:, content:, resume:) -> todo
    ShowDirectoryPicker(resume:) -> {
      use result <- promise.map(show_save_directory_picker())
      resume(result)
    }
    WriteToClipboard(text:, resume:) -> {
      use result <- promise.map(clipboard.write_text(text))
      resume(result)
    }
  }
}

//     state.SetFlushTimer(reference) ->
//       effect.from(fn(dispatch) {
//         promise.map(promise.wait(2000), fn(_: Nil) {
//           dispatch(state.FlushTimeout(reference:))
//         })
//         Nil
//       })
//     state.SaveFile(handle:, filename:, projection:) -> {
//       effect.from(fn(_dispatch) {
//         {
//           let name = case filename.1 {
//             state.EygJson -> filename.0 <> ".eyg.json"
//           }
//           use file_handle <- promise.try_await(file_system.get_file_handle(
//             handle,
//             name,
//             True,
//           ))

//           use writable <- promise.try_await(file_system.create_writable(
//             file_handle,
//           ))
//           let content =
//             projection.rebuild(projection)
//             |> editable.to_annotated([])
//             |> dag_json.to_block()

//           use Nil <- promise.try_await(file_system.write(writable, content))
//           use Nil <- promise.try_await(file_system.close(writable))
//           promise.resolve(Ok(Nil))
//         }
//         |> promise.map(fn(r) { echo r })
//         Nil
//       })
//     }
//     state.SpotlessConnect(effect_counter:, origin:, service:) -> {
//       let assert Some(port) = origin.port
//       effect.from(fn(dispatch) {
//         promise.map(browser.run_task(spotless.dnsimple(port)), fn(result) {
//           dispatch(state.SpotlessConnected(
//             reference: effect_counter,
//             service:,
//             result:,
//           ))
//         })
//         Nil
//       })
//     }

//   }
// }

// fn run_effect(effect) {
//   case effect {
//     state.Alert(message) -> alert.run(message)
//     state.Copy(text) -> copy.run(text)
//     state.Download(file) -> download.run(file)
//     state.Fetch(request) -> fetch.run(request)
//     state.Geolocation -> geolocation.run()
//     state.Now -> now.run()
//     state.Paste -> paste.run()
//     state.Prompt(message) -> prompt.run(message)
//     state.Random(max) -> promise.resolve(random.encode(random.sync(max)))
//     state.Visit(uri) -> {
//       let result =
//         browser.open(uri.to_string(uri), #(800, 400))
//         |> result.replace(Nil)
//       promise.resolve(visit.encode(result))
//     }
//   }
// }

@external(javascript, "../../website_ffi.mjs", "show_save_directory_picker")
fn show_save_directory_picker() -> promise.Promise(
  Result(file_system.Handle(file_system.D), String),
)
// // @external(javascript, "../../website_ffi.mjs", "get_persisted_directory")
// // fn get_persisted_directory() -> promise.Promise(
// //   Result(file_system.Handle(file_system.D), String),
// // )
