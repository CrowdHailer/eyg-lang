import eyg/interpreter/state
import eyg/interpreter/value as v
import gleam/http/request
import gleam/http/response.{type Response}
import gleam/result
import midas/effect
import ogre/operation.{type Operation}
import pal/system
import touch_grass/copy
import touch_grass/decode_json
import touch_grass/fetch
import touch_grass/flip
import touch_grass/harness/browser
import touch_grass/interface
import touch_grass/now
import touch_grass/paste
import touch_grass/print
import touch_grass/prompt
import touch_grass/random
import touch_grass/visit

pub fn cast(
  label: String,
  lift: state.Value(m),
) -> Result(browser.Effect, state.Reason(m)) {
  interface.cast(browser.effects(), label, lift)
}

fn done(encode) {
  fn(value) { system.Done(encode(value)) }
}

fn unit_return() {
  fn() { system.Done(v.unit()) }
}

pub type Action {
  Abort(String)
  Work(system.Effect(state.Value(List(Int))))
  Spotless(service: browser.Service, operation: Operation(BitArray))
}

/// Handle the external implementation of an effect from an EYG script
/// 
/// This works on the explicit `system.Effect` type,
/// a defunctionalized reification of a continuation monad.
/// We use the explicit version because:
/// 
/// - Matching on Done is useful for sync actions
/// - Passing in the implementations of write_to_clipboard is verbose
/// 
/// ## Spotless integration
/// This requires state to be kept somewhere, rejected approaches include
/// - state in the system/browser
///   Add a GetKey/SetKey added to the `system.Effect`,
///   This keeps values in memory but conflicts is other parts of the app use it.
///   Doesn't solve deleting the key if response is denied due to expired token.
/// - state in the platform implementation
///   Add a state parameter to the extrinsic implementation return state and create a message type of WorkDone/Connected
///   This would require the addition of a process identifier or address so that connecting would then allow a follow up workdone message.
///   This is a lot of complexity ontop of the current implementation.
/// - A proxy functionality on the http effect.
///   This is similar to how the idea of a stateful auth proxy would work.
///   But is the most untyped because falls back to an eyg value representation of a request
/// 
/// There is a lot of choice about how the application chooses to present a spotless integration.
/// It is best to keep state in one place, the application.
/// Behaviour is different from using the spotless proxy where the client keeps state and the spotless hub where the server keeps state.
/// The implementation of `extrinsic` should be unchanged for those changes, so just returns intent
pub fn extrinsic(effect: browser.Effect) -> Action {
  case effect {
    browser.Abort(reason) -> Abort(reason)
    browser.Alert(message) -> Work(system.Alert(message, unit_return()))
    browser.Copy(text) -> Work(system.WriteToClipboard(text, done(copy.encode)))
    browser.DecodeJson(raw) -> Work(system.Done(decode_json.sync(raw)))
    browser.Download(input) -> Work(system.Download(input, unit_return()))
    browser.Fetch(request) -> Work(fetch(request))
    browser.Flip -> Work(system.Done(flip.encode(flip.sync())))
    browser.Now -> Work(system.Done(now.encode(now.sync())))
    browser.Paste -> Work(system.ReadFromClipboard(done(paste.encode)))
    browser.Print(message) ->
      Work(system.Done(print.encode(print.sync(message))))
    browser.Prompt(question) ->
      Work(system.Prompt(question, done(prompt.encode)))
    browser.Random(max) -> Work(system.Done(random.encode(random.sync(max))))
    browser.Visit(uri) -> Work(system.Visit(uri, done(visit_encode)))
    browser.Spotless(service:, operation:) -> Spotless(service:, operation:)
  }
}

pub fn fetch(
  request: request.Request(BitArray),
) -> system.Effect(v.Value(a, b)) {
  system.Fetch(request, done(fetch_encode))
}

fn fetch_encode(
  result: Result(Response(BitArray), effect.FetchError),
) -> v.Value(a, b) {
  result
  |> result.map_error(describe_fetch_error)
  |> fetch.encode
}

fn describe_fetch_error(reason) {
  case reason {
    effect.NetworkError(description) -> "network error: " <> description
    effect.UnableToReadBody -> "unable to read body"
    effect.NotImplemented -> "not implemented"
  }
}

fn visit_encode(result) {
  result
  |> result.replace(Nil)
  |> visit.encode
}
