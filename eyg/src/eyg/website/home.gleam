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

fn p(text) {
  h.p([], [element.text(text)])
}

pub fn snippet(state, i) {
  snippet.render(state.get_snippet(state, i))
  |> element.map(state.SnippetMessage(i, _))
}

fn render(state) {
  h.div([a.class("yellow-gradient")], [
    components.header(),
    h.div([a.class("mx-auto max-w-2xl")], [
      snippet(state, 0),
      p("hello"),
      p(
        "EYG has controlled effects this means any program can be inspected to see what it needs from the environment it runs in.
      For example these snippets have an alert effect",
      ),
      p("Download is an even better effect in the browser"),
      p("There are hashes that allow reproducable everything"),
    ]),
  ])
}
