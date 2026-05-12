//// Browser is the API to the platform
//// It might make sense to implement a version of the effect interface built on this

import gleam/bit_array
import gleam/fetch
import gleam/fetchx
import gleam/http/request
import gleam/http/response
import gleam/int
import gleam/javascript/promise.{type Promise}
import gleam/javascript/promisex
import gleam/json.{type Json}
import gleam/result
import gleam/string
import gleam/uri
import midas/browser
import ogre/origin
import plinth/browser/clipboard
import plinth/browser/file
import plinth/browser/file_system
import plinth/browser/location
import plinth/browser/window
import plinth/browser/window_proxy
import snag
import spotless
import spotless/oauth_2_1
import spotless/oauth_2_1/authorization
import spotless/oauth_2_1/token
import spotless/proof_key_for_code_exchange as pkce
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
  // Follow(uri: uri.Uri, resume: fn(Result(uri.Uri, fetch.FetchError)) -> m)
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
  Spotless(
    service: harness.Service,
    origin: origin.Origin,
    resume: fn(Result(token.Response, String)) -> m,
  )
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
pub fn run(effect: Effect(m)) -> Promise(m) {
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
    // Follow(uri:, resume:) -> todo
    LoadFiles(handle: _) -> {
      panic as "this shouldn't read every file"
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
    SaveFile(handle: _, filename: _, content: _, resume: _) ->
      panic as "unsupported browser effect"
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
    Spotless(service:, origin:, resume:) -> {
      use result <- promise.map(spotless(origin, service))
      resume(result)
    }
  }
}

fn spotless(
  origin: origin.Origin,
  service: harness.Service,
) -> Promise(Result(token.Response, String)) {
  let client_id = origin.to_string(origin)
  use bytes <- promisex.try_sync(browser.do_random(32))
  let code_challenge = bit_array.base64_url_encode(bytes, False)
  let code_challenge_method = pkce.Plain
  let code_verifier = code_challenge

  let redirect_uri =
    uri.Uri(..origin.to_uri(origin), path: "/") |> uri.to_string

  let #(service, scope) = case service {
    harness.DNSimple -> #("dnsimple", [])
    harness.GitHub -> #("github", [])
    harness.Vimeo -> #("vimeo", [])
  }
  use server <- promisex.try_sync(
    spotless.server(service)
    |> result.replace_error("unknown service " <> service),
  )

  let request =
    authorization.Request(
      client_id:,
      code_challenge:,
      code_challenge_method:,
      redirect_uri:,
      scope:,
      state: "",
      extra: [],
    )

  let redirect =
    authorization.request_to_url(server.authorization_endpoint, request)
  // which or location or href throws the exception

  use redirect <- promise.await(do_follow(redirect))
  use redirect <- promisex.try_sync(redirect)
  use redirect <- promisex.try_sync(
    uri.parse(redirect) |> result.replace_error("invalid redirect_url"),
  )
  use response <- promisex.try_sync(
    oauth_2_1.authorization_response_from_uri(redirect)
    |> result.map_error(snag.line_print),
  )

  let oauth_2_1.AuthorizationServer(token_endpoint:, ..) = server

  let request =
    token.Request(
      grant_type: token.AuthorizationCode,
      client_id:,
      code: response.code,
      code_verifier:,
      redirect_uri: redirect_uri,
    )

  let request = token.request_to_http(token_endpoint, request)
  use result <- promise.await(fetchx.send_bits(request))
  use response <- promisex.try_sync(
    result
    |> result.map_error(fn(reason) {
      "failed to fetch token: " <> string.inspect(reason)
    }),
  )
  use response <- promisex.try_sync(
    oauth_2_1.token_response_from_http(response)
    |> result.map_error(snag.line_print),
  )
  let response =
    response
    |> result.map_error(string.inspect)

  promise.resolve(response)
}

fn do_follow(url) {
  let url = uri.to_string(url)
  let frame = #(600, 700)
  let assert Ok(popup) = open(url, frame)
  receive_redirect(popup, 100)
}

pub fn open(url, frame_size) {
  let space = #(
    window.outer_width(window.self()),
    window.outer_height(window.self()),
  )
  let #(#(offset_x, offset_y), #(inner_x, inner_y)) = center(frame_size, space)
  let features =
    string.concat([
      "popup",
      ",width=",
      int.to_string(inner_x),
      ",height=",
      int.to_string(inner_y),
      ",left=",
      int.to_string(offset_x),
      ",top=",
      int.to_string(offset_y),
    ])

  window.open(url, "_blank", features)
}

pub fn center(inner, outer) {
  let #(inner_x, inner_y) = inner
  let #(outer_x, outer_y) = outer

  let inner_x = int.min(inner_x, outer_x)
  let inner_y = int.min(inner_y, outer_y)

  let offset_x = { outer_x - inner_x } / 2
  let offset_y = { outer_y - inner_y } / 2

  #(#(offset_x, offset_y), #(inner_x, inner_y))
}

fn receive_redirect(popup, wait) {
  use Nil <- promise.await(promise.wait(wait))
  case href(window_proxy.location(popup)) |> echo {
    Ok("http" <> _) as location -> {
      window_proxy.close(popup)
      promise.resolve(location)
    }
    _ -> receive_redirect(popup, wait)
  }
}

// Needs to return result as location on cross origin is an error
@external(javascript, "./browser_ffi.mjs", "href")
fn href(location: location.Location) -> Result(String, String)

@external(javascript, "../../website_ffi.mjs", "show_save_directory_picker")
fn show_save_directory_picker() -> Promise(
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
