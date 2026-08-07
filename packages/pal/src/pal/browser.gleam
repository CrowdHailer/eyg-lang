//// Browser is the API to the platform
//// It might make sense to implement a version of the effect interface built on this

import gleam/bit_array
import gleam/fetch
import gleam/fetchx
import gleam/http/request
import gleam/http/response.{Response}
import gleam/int
import gleam/javascript/promise.{type Promise}
import gleam/javascript/promisex
import gleam/json.{type Json}
import gleam/option.{type Option}
import gleam/result
import gleam/string
import gleam/uri
import midas/continuation.{type Continuation as K}
import midas/effect
import ogre/origin
import plinth/browser/clipboard
import plinth/browser/crypto
import plinth/browser/file
import plinth/browser/file_system
import plinth/browser/location
import plinth/browser/window
import plinth/browser/window_proxy
import spotless
import spotless/oauth_2_1
import spotless/oauth_2_1/authorization
import spotless/oauth_2_1/token
import spotless/proof_key_for_code_exchange as pkce
import touch_grass/download
import touch_grass/harness/browser as harness

/// The browser platform effect
///
/// - `FocusOnInput` focus on the first input on the page.
///   This seems to be unnecessary if only one autofocused input, and the code doesn't have a tabindex
/// 
/// This could return a list of effects for asynchrony or a Done(m) to allow serial effects
pub type Effect(m) {
  Done(m)
  Alert(message: String, resume: fn() -> Effect(m))
  Download(input: download.Input, resume: fn() -> Effect(m))
  Fetch(
    request: request.Request(BitArray),
    resume: fn(Result(response.Response(BitArray), effect.FetchError)) ->
      Effect(m),
  )
  FetchStreamResponse(
    request: request.Request(BitArray),
    resume: fn(Result(response.Response(Reader), fetch.FetchError)) -> Effect(m),
  )
  // Follow(uri: uri.Uri, resume: fn(Result(uri.Uri, fetch.FetchError)) -> Effect(m))
  // FocusOnInput(resume:)
  // LoadFiles(handle: file_system.DirectoryHandle)
  OpenPopup(
    location: String,
    resume: fn(Result(window_proxy.WindowProxy, String)) -> Effect(m),
  )
  PostMessage(
    target: window_proxy.WindowProxy,
    payload: Json,
    resume: fn(Nil) -> Effect(m),
  )
  Prompt(question: String, resume: fn(Result(String, Nil)) -> Effect(m))
  ReadFromClipboard(resume: fn(Result(String, String)) -> Effect(m))
  ReadChunk(
    reader: Reader,
    resume: fn(Result(Option(BitArray), fetch.FetchError)) -> Effect(m),
  )
  SaveFile(
    handle: file_system.DirectoryHandle,
    filename: String,
    content: BitArray,
    resume: fn(Result(Nil, String)) -> Effect(m),
  )
  ShowDirectoryPicker(
    resume: fn(Result(file_system.Handle(file_system.D), String)) -> Effect(m),
  )
  // TODO move to Follow etc but needs secure random and ability to combine effects
  // TODO browser shouldn't rely on harness but no circular dependency yet
  Spotless(
    service: harness.Service,
    origin: origin.Origin,
    resume: fn(Result(token.Response, String)) -> Effect(m),
  )
  Visit(
    uri: uri.Uri,
    resume: fn(Result(window_proxy.WindowProxy, String)) -> Effect(m),
  )
  WriteToClipboard(text: String, resume: fn(Result(Nil, String)) -> Effect(m))
}

pub fn then(effect: Effect(a), func: fn(a) -> Effect(b)) -> Effect(b) {
  case effect {
    Done(value) -> func(value)
    Fetch(request, resume) ->
      Fetch(request, fn(response) { then(resume(response), func) })
    Alert(message, resume) -> Alert(message, fn() { then(resume(), func) })
    Download(input, resume) -> Download(input, fn() { then(resume(), func) })
    FetchStreamResponse(request, resume) ->
      FetchStreamResponse(request, fn(response) { then(resume(response), func) })
    // LoadFiles(handle) -> todo
    OpenPopup(location, resume) ->
      OpenPopup(location, fn(x) { then(resume(x), func) })
    PostMessage(target, payload, resume) ->
      PostMessage(target, payload, fn(x) { then(resume(x), func) })
    Prompt(question, resume) ->
      Prompt(question, fn(x) { then(resume(x), func) })
    ReadFromClipboard(resume) ->
      ReadFromClipboard(fn(x) { then(resume(x), func) })
    ReadChunk(reader, resume) ->
      ReadChunk(reader, fn(x) { then(resume(x), func) })
    SaveFile(handle, filename, content, resume) ->
      SaveFile(handle, filename, content, fn(x) { then(resume(x), func) })
    ShowDirectoryPicker(resume) ->
      ShowDirectoryPicker(fn(x) { then(resume(x), func) })
    Spotless(service, origin, resume) ->
      Spotless(service, origin, fn(x) { then(resume(x), func) })
    Visit(uri, resume) -> Visit(uri, fn(x) { then(resume(x), func) })
    WriteToClipboard(text, resume) ->
      WriteToClipboard(text, fn(x) { then(resume(x), func) })
  }
}

pub fn map(effect: Effect(a), func: fn(a) -> b) -> Effect(b) {
  then(effect, fn(value) { Done(func(value)) })
}

pub fn fetch(
  request: request.Request(BitArray),
) -> K(Effect(r), Result(response.Response(BitArray), effect.FetchError)) {
  fn(resume) { Fetch(request:, resume:) }
}

pub type Reader =
  fn() -> Promise(Result(Option(BitArray), fetch.FetchError))

// Use an ignore event if we don't want a message
pub fn run(effect: Effect(m)) -> Promise(m) {
  case effect {
    Done(value) -> promise.resolve(value)
    Alert(message:, resume:) -> {
      window.alert(message)
      run(resume())
    }
    Download(input:, resume:) -> {
      download_file(input)
      run(resume())
    }
    Fetch(request:, resume:) -> {
      use result <- promise.await(fetchx.send_bits(request))
      let result =
        result.map_error(result, fn(reason) {
          case reason {
            fetch.NetworkError(detail) -> effect.NetworkError(detail)
            fetch.UnableToReadBody -> effect.UnableToReadBody
            fetch.InvalidJsonBody -> effect.UnableToReadBody
          }
        })
      run(resume(result))
    }
    FetchStreamResponse(request:, resume:) -> {
      use result <- promise.await(fetch.send_bits(request))
      case result {
        Ok(response) ->
          case fetch.stream_body(response) {
            Ok(reader) -> {
              let reader = fn() { fetch.read_chunk(reader) }
              run(resume(Ok(Response(..response, body: reader))))
            }
            Error(reason) -> run(resume(Error(reason)))
          }
        Error(reason) -> run(resume(Error(reason)))
      }
    }

    // Follow(uri:, resume:) -> todo
    // LoadFiles(handle: _) -> {
    //   panic as "this shouldn't read every file"
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
    // }
    OpenPopup(location:, resume:) -> {
      run(resume(open(location, #(650, 800))))
    }
    Prompt(question:, resume:) -> run(resume(window.prompt(question)))

    PostMessage(target:, payload:, resume:) ->
      run(resume(window_proxy.post_message(target, payload, "*")))
    ReadChunk(reader, resume) -> {
      use result <- promise.await(reader())
      run(resume(result))
    }
    ReadFromClipboard(resume) -> {
      use result <- promise.await(clipboard.read_text())
      run(resume(result))
    }
    SaveFile(handle: _, filename: _, content: _, resume: _) ->
      panic as "unsupported browser effect"
    ShowDirectoryPicker(resume:) -> {
      use result <- promise.await(show_save_directory_picker())
      run(resume(result))
    }
    Visit(uri:, resume:) -> {
      run(resume(open(uri.to_string(uri), #(800, 400))))
    }
    WriteToClipboard(text:, resume:) -> {
      use result <- promise.await(clipboard.write_text(text))
      run(resume(result))
    }
    Spotless(service:, origin:, resume:) -> {
      use result <- promise.await(spotless(origin, service))
      run(resume(result))
    }
  }
}

fn spotless(
  origin: origin.Origin,
  service: harness.Service,
) -> Promise(Result(token.Response, String)) {
  let client_id = origin.to_string(origin)
  use bytes <- promisex.try_sync(do_random(32))
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
  use response <- promisex.try_sync(oauth_2_1.authorization_response_from_uri(
    redirect,
  ))

  use response <- promisex.try_sync(case response.result {
    Ok(response) -> Ok(response)
    Error(response) -> Error(response.error)
  })

  let oauth_2_1.AuthorizationServer(token_endpoint:, ..) = server

  let request =
    token.AuthorizationCode(
      client_id:,
      code: response,
      code_verifier:,
      // redirect_uri: redirect_uri,
    )

  let request = token.authorization_code_to_http(token_endpoint, request)
  use result <- promise.await(fetchx.send_bits(request))
  use response <- promisex.try_sync(
    result
    |> result.map_error(fn(reason) {
      "failed to fetch token: " <> string.inspect(reason)
    }),
  )
  use response <- promisex.try_sync(
    oauth_2_1.token_response_from_http(response)
    |> result.map_error(string.inspect),
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

@external(javascript, "./browser_ffi.mjs", "show_save_directory_picker")
fn show_save_directory_picker() -> Promise(
  Result(file_system.Handle(file_system.D), String),
)

// // @external(javascript, "../../website_ffi.mjs", "get_persisted_directory")
// // fn get_persisted_directory() -> promise.Promise(
// //   Result(file_system.Handle(file_system.D), String),
// // )
@external(javascript, "./browser_ffi.mjs", "downloadFile")
fn do_download_file(file: file.File) -> Nil

pub fn download_file(input) {
  let download.Input(name:, content:) = input
  let file = file.new(content, name)
  do_download_file(file)
}

fn do_random(length) {
  case window.crypto(window.self()) {
    Ok(crypto) ->
      case crypto.get_random_values(crypto, length) {
        Ok(bytes) -> Ok(bytes)
        Error(reason) -> Error(reason)
      }
    Error(Nil) -> Error("no crypto")
  }
}
// A loop that returns run and any effects needs a pattern match of run
// To separate return
// Maybe(a new cache status or not.)
// Done
// Tasked(but whats in here) it also needs mapping

// Yes this works but what if I want the parsed effect in the history
// pub type Working {
//   Done
//   Effect
//   Dependency
// }

// fn handle(return: #(Return, Working)) {
//   case return {
//     #(Error(break.UnhandledEffect(label)), Effect) -> todo
//   }
// }
