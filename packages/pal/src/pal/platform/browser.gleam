import eyg/interpreter/state
import eyg/interpreter/value as v
import gleam/http/response.{type Response}
import gleam/result
import midas/effect
import pal/browser as system
import touch_grass/copy
import touch_grass/decode_json
import touch_grass/fetch
import touch_grass/flip
import touch_grass/harness/browser
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
  browser.cast(label, lift)
}

fn done(encode) {
  fn(value) { system.Done(encode(value)) }
}

fn unit_return() {
  fn() { system.Done(v.unit()) }
}

/// Handle the external implementation of an effect
/// 
/// This works on the explicit system.Effect type,
/// a defunctionalized reification of a continuation monad.
/// We use the explicit version because:
/// 
/// - Matching on Ok(Done) is useful for sync actions
/// - Passing in the implementations of write_to_clipboard is verbose
pub fn extrinsic(effect) {
  case effect {
    browser.Abort(reason) -> Error(reason)
    browser.Alert(message) -> Ok(system.Alert(message, unit_return()))
    browser.Copy(text) -> Ok(system.WriteToClipboard(text, done(copy.encode)))
    browser.DecodeJson(raw) -> Ok(system.Done(decode_json.sync(raw)))
    browser.Download(input) -> Ok(system.Download(input, unit_return()))
    browser.Fetch(request) -> Ok(system.Fetch(request, done(fetch_encode)))
    browser.Flip -> Ok(system.Done(flip.encode(flip.sync())))
    browser.Now -> Ok(system.Done(now.encode(now.sync())))
    browser.Paste -> Ok(system.ReadFromClipboard(done(paste.encode)))
    browser.Print(message) -> Ok(system.Done(print.encode(print.sync(message))))
    browser.Prompt(question) -> Ok(system.Prompt(question, done(prompt.encode)))
    browser.Random(max) -> Ok(system.Done(random.encode(random.sync(max))))
    browser.Visit(uri) -> Ok(system.Visit(uri, done(visit_encode)))
    browser.Spotless(..) -> Error("unsupported")
    // browser.Spotless(service:, operation:) -> {
    //   let value = case token(context, service) {
    //     Ok(token) -> {
    //       let request =
    //         service_request(service, operation, token, context.hub_origin)
    //       browser.fetch(request, handled(c, fetch.encode, context))
    //       |> handle(env, k, c, updated)
    //     }
    //     Error(_) -> {
    //       let connecting =
    //         list.append(updated.connecting, [#(c, service, operation)])
    //       let updated = Context(..updated, connecting:)
    //       #(Handling(c, env, k), updated, [
    //         browser.Spotless(
    //           service,
    //           context.hub_origin,
    //           context.connect_completed(service, _),
    //         ),
    //       ])
    //     }
    //   }
    //   value
    // }
  }
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
