import eyg/ir/dag_json
import gleam/bit_array
import gleam/int
import gleam/io
import gleam/javascript/array
import gleam/javascript/promise
import gleam/javascript/promisex
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import lustre
import lustre/effect
import midas/browser
import morph/editable as e
import plinth/browser/document
import plinth/browser/element
import plinth/javascript/console
import website/components/snippet
import website/harness/browser as harness
import website/sync/cache

pub fn run() {
  let scripts = document.query_selector_all("[type='application/json+eyg']")
  // let cache = sync.init(sync.test_origin)
  // use result <- promise.map(browser.run(remote.load_task()))
  // let assert Ok(dump) = result
  // let cache = sync.load(cache, dump)
  io.debug("load the original")
  let cache = cache.init()

  list.index_map(array.to_list(scripts), fn(script, i) {
    console.log(script)
    let id = "eyg" <> int.to_string(i)
    let json = element.inner_text(script)

    element.insert_adjacent_html(
      script,
      element.AfterEnd,
      "<div id=\"" <> id <> "\"></div>",
    )
    let json = string.replace(json, "&quot;", "\"")
    let assert Ok(source) = dag_json.from_block(bit_array.from_string(json))
    // ORIGIN is not used when pulling from supabase
    let app =
      lustre.application(init, update, snippet.render_embedded_with_menu(
        _,
        None,
      ))
    let assert Ok(_) = lustre.start(app, "#" <> id, #(source, cache))
  })
}

fn init(config) {
  let #(source, cache) = config
  let source =
    e.from_annotated(source)
    |> e.open_all
  let snippet =
    snippet.init(
      source,
      // , [], effects(), cache
    )
  #(snippet, effect.none())
}

fn dispatch_to_snippet(promise) {
  effect.from(fn(d) { promisex.aside(promise, fn(message) { d(message) }) })
}

fn dispatch_nothing(_promise) {
  effect.none()
}

fn update(snippet, message) {
  let #(snippet, eff) = snippet.update(snippet, message)
  let #(failure, snippet_effect) = case eff {
    snippet.Nothing -> #(None, effect.none())
    snippet.NewCode -> #(None, effect.none())
    snippet.Confirm -> #(None, effect.none())
    snippet.Failed(failure) -> #(Some(failure), effect.none())
    snippet.ReturnToCode -> #(None, dispatch_nothing(snippet.focus_on_buffer()))
    snippet.FocusOnInput -> #(None, dispatch_nothing(snippet.focus_on_input()))
    snippet.ToggleHelp -> #(None, effect.none())
    snippet.MoveAbove -> #(None, effect.none())
    snippet.MoveBelow -> #(None, effect.none())
    snippet.ReadFromClipboard -> #(
      None,
      dispatch_to_snippet(snippet.read_from_clipboard()),
    )
    snippet.WriteToClipboard(text) -> #(
      None,
      dispatch_to_snippet(snippet.write_to_clipboard(text)),
    )
  }
  io.debug(failure)
  #(snippet, snippet_effect)
}

fn effects() {
  harness.effects()
  // |> list.append([
  //   #(
  //     netlify_deploy_site.l,
  //     #(
  //       netlify_deploy_site.lift(),
  //       netlify_deploy_site.reply(),
  //       netlify_deploy_site.blocking(netlify.local, _),
  //     ),
  //   ),
  //   #(
  //     tweet.l,
  //     #(tweet.lift(), tweet.reply(), tweet.blocking(
  //       twitter.client_id,
  //       twitter.redirect_uri,
  //       True,
  //       _,
  //     )),
  //   ),
  // ])
}
