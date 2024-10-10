import eyg/website/components
import eyg/website/components/snippet
import eyg/website/home/state
import eyg/website/page
import lustre
import lustre/attribute as a
import lustre/element
import lustre/element/html as h

pub fn page(bundle) {
  page.app("eyg/website/home", "client", bundle)
}

pub fn client() {
  let app = lustre.application(state.init, state.update, render)
  let assert Ok(_) = lustre.start(app, "#app", Nil)
  Nil
}

fn h2(header) {
  h.h2([a.class("text-2xl")], [element.text(header)])
}

fn p(text) {
  h.p([], [element.text(text)])
}

pub fn snippet(state, i) {
  snippet.render(state.get_snippet(state, i))
  |> element.map(state.SnippetMessage(i, _))
}

fn section(title, content) {
  page_area([
    h.div([a.class("mx-auto w-full max-w-3xl my-12")], [h2(title), ..content]),
  ])
}

fn page_area(content) {
  h.div([a.style([#("min-height", "100vh")]), a.class("vstack")], content)
}

fn render(s) {
  h.div([a.class("yellow-gradient")], [
    page_area([
      components.header(),
      h.div([a.class("expand hstack")], [
        h.div([a.class("m-2")], [
          h.p([a.class("max-w-lg")], [
            element.text(
              "The stable foundation for building software that runs forever.",
            ),
          ]),
          h.p([], [
            h.span([a.class("font-bold")], [element.text("Predictable:")]),
            element.text(
              " programs are deterministic, dependencies are immutable",
            ),
          ]),
          h.p([], [
            h.span([a.class("font-bold")], [element.text("Useful:")]),
            element.text(
              " run anywhere, managed effects allow programs to declare runtime requirements",
            ),
          ]),
          h.p([], [
            h.span([a.class("font-bold")], [element.text("Confident:")]),
            element.text(
              " A sound structural type system guarantees programs never crash",
            ),
          ]),
        ]),
        h.p([a.class("m-12 text-8xl")], [element.text("EYG")]),
      ]),
    ]),
    section("Closure serialisation", [
      snippet(s, state.closure_serialization_key),
      p(
        "Closure serialisation allows functions to be efficiently transformed back into source code and sent to other machines.",
      ),
      // p("hello"),
    // p(
    //   "EYG has controlled effects this means any program can be inspected to see what it needs from the environment it runs in.
    // For example these snippets have an alert effect",
    // ),
    // p("Download is an even better effect in the browser"),
    // p("There are hashes that allow reproducable everything"),
    ]),
    section("run everywhere", [
      snippet(s, state.twitter_key),
      p("Integrate into services"),
    ]),
    section("Immutable references", [
      snippet(s, state.fetch_key),
      p(
        "All declarations can be uniquely hashed and referenced from other code.",
      ),
      p(
        "Once a dependency is fixed it can never change because changing the hash would update your program's hash.",
      ),
    ]),
    // section("Immutable references", [snippet(s, state.hash_key)]),
  ])
}
