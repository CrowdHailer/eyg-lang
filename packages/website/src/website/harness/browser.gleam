//// Browser is the API to the platform
//// It might make sense to implement a version of the effect interface built on this

import gleam/fetch
import gleam/fetchx
import gleam/http/request
import gleam/http/response
import gleam/javascript/promise
import gleam/json.{type Json}
import gleam/result
import gleam/string
import gleam/uri
import midas/browser
import plinth/browser/clipboard
import plinth/browser/file
import plinth/browser/file_system
import plinth/browser/window
import plinth/browser/window_proxy
import touch_grass/download
import website/harness/harness

/// The browser platform effect
///
/// - `FocusOnInput` focus on the first input on the page.
///   This seems to be unnecessary if only one autofocused input, and the code doesn't have a tabindex
/// 
/// This could return a list of effects for asynchrony or a Done(m) to allow serial effects
pub type Effect(m) {
  Alert(message: String, resume: fn() -> m)
  Download(input: download.Input, resume: fn() -> m)
  Fetch(
    request: request.Request(BitArray),
    resume: fn(Result(response.Response(BitArray), fetch.FetchError)) -> m,
  )
  Follow(uri: uri.Uri, resume: fn(Result(uri.Uri, fetch.FetchError)) -> m)
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
  Prompt(question: String, resume: fn(Result(String, Nil)) -> m)
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
  // TODO move to Follow etc but needs secure random and ability to combine effects
  // TODO browser shouldn't rely on harness but no circular dependency yet
  Spotless(service: harness.Service, resume: fn(Result(String, String)) -> m)
  Visit(uri: uri.Uri, resume: fn(Result(window_proxy.WindowProxy, String)) -> m)
  WriteToClipboard(text: String, resume: fn(Result(Nil, String)) -> m)
}

pub fn fetch(request, resume) {
  Fetch(request:, resume: fn(result) {
    resume(result.map_error(result, string.inspect))
  })
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
    Alert(message:, resume:) -> {
      window.alert(message)
      promise.resolve(resume())
    }
    Download(input:, resume:) -> {
      download_file(input)
      promise.resolve(resume())
    }
    Fetch(request:, resume:) -> {
      use result <- promise.map(fetchx.send_bits(request))
      resume(result)
    }
    Follow(uri:, resume:) -> todo
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
    Prompt(question:, resume:) ->
      promise.resolve(resume(window.prompt(question)))

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
    Visit(uri:, resume:) -> {
      promise.resolve(resume(browser.open(uri.to_string(uri), #(800, 400))))
    }
    WriteToClipboard(text:, resume:) -> {
      use result <- promise.map(clipboard.write_text(text))
      resume(result)
    }
    Spotless(service:, resume:) -> todo
  }
}

// pub fn read(name) {
//   use dir <- promise.try_await(file_system.show_directory_picker())
//   use file <- promise.try_await(file_system.get_file_handle(dir, name, True))
//   use file <- promise.try_await(file_system.get_file(file))
//   use text <- promise.map(file.bytes(file))
//   Ok(text)
// }
// pub fn list() {
//   use dir <- promise.try_await(file_system.show_directory_picker())
//   use #(entries, _) <- promise.try_await(file_system.all_entries(dir))
//   promise.resolve(Ok(list.map(array.to_list(entries), string.inspect)))
// }
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
//     state.Fetch(request) -> fetch.run(request)
//     state.Geolocation -> geolocation.run()
//     state.Now -> now.run()

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
@external(javascript, "../../website_ffi.mjs", "downloadFile")
fn do_download_file(file: file.File) -> Nil

pub fn download_file(input) {
  let download.Input(name:, content:) = input
  let file = file.new(content, name)
  do_download_file(file)
}
