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
  h.div([a.class("mx-auto max-w-3xl my-12")], [h2(title), ..content])
}

fn render(state) {
  h.div([a.class("yellow-gradient")], [
    components.header(),
    section("Closure serialisation", [
      snippet(state, 0),
      p("hello"),
      p(
        "EYG has controlled effects this means any program can be inspected to see what it needs from the environment it runs in.
      For example these snippets have an alert effect",
      ),
      p("Download is an even better effect in the browser"),
      p("There are hashes that allow reproducable everything"),
    ]),
    section("Effects", [snippet(state, 1)]),
  ])
}
