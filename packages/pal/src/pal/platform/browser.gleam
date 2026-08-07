import eyg/interpreter/state
import eyg/interpreter/value as v
import midas/continuation.{type Continuation as K}
import pal/browser as system
import touch_grass/flip
import touch_grass/harness/browser

pub fn cast(
  label: String,
  lift: state.Value(m),
) -> Result(browser.Effect, state.Reason(m)) {
  browser.cast(label, lift)
}

fn alert(message: String) -> K(system.Effect(t), Nil) {
  fn(resume) { system.Alert(message, fn() { resume(Nil) }) }
}

fn read_from_clipboard() -> K(system.Effect(t), Result(String, String)) {
  system.ReadFromClipboard
}

fn tmp() {
  use Nil <- continuation.then(alert("Hi"))
  todo
}

pub fn e2(effect) {
  Ok({
    use x <- continuation.then(alert("hi"))
    continuation.return(v.unit())
  })
}

/// handle the external implementation of an effect
pub fn extrinsic(effect) {
  case effect {
    browser.Abort(reason) -> Error(reason)
    browser.Alert(message) ->
      Ok(system.Alert(message, fn() { system.Done(v.unit()) }))

    // browser.Copy(text) ->
    //   browser.WriteToClipboard(text, handled(c, copy.encode, context))
    //   |> handle(env, k, c, updated)
    // browser.DecodeJson(raw) ->
    //   loop(resume(decode_json.sync(raw), env, k), context, resume)
    // browser.Download(input) ->
    //   browser.Download(input, fn() { context.handled(c, v.unit()) })
    //   |> handle(env, k, c, updated)
    // browser.Fetch(request) ->
    //   browser.fetch(request, handled(c, fetch.encode, context))
    //   |> handle(env, k, c, updated)
    browser.Flip ->
      flip.encode(flip.sync())
      |> system.Done()
      |> Ok()
    // browser.Now ->
    //   now.encode(now.sync())
    //   |> resume(env, k)
    //   |> loop(context, resume)
    // browser.Paste ->
    //   browser.ReadFromClipboard(handled(c, paste.encode, context))
    //   |> handle(env, k, c, updated)
    // browser.Print(message) ->
    //   print.encode(print.sync(message))
    //   |> resume(env, k)
    //   |> loop(context, resume)
    // browser.Prompt(question) ->
    //   browser.Prompt(question, handled(c, prompt.encode, context))
    //   |> handle(env, k, c, updated)
    // browser.Random(max) ->
    //   random.encode(random.sync(max))
    //   |> resume(env, k)
    //   |> loop(context, resume)
    // // browser.Sleep(max) -> todo
    // // sleep.encode(sleep.sync(max))
    // // |> resume(env, k)
    // // |> loop(context, resume)
    // browser.Visit(uri) ->
    //   browser.Visit(uri:, resume: fn(result) {
    //     todo
    //     // let value = case result {
    //     //   Ok(_ -> v.ok(v.unit())
    //     //   Error(reason -> v.error(v.String(reason))
    //     // }
    //     // context.handled(c, value)
    //   })
    //   |> handle(env, k, c, updated)
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
    _ -> todo
    // Error(reason -> #(Exception(reason), context, [])
  }
}
