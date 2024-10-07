import eyg/website/components
import eyg/website/components/snippet
import eyg/website/home/state
import eyg/website/page
import harness/impl/browser/alert
import harness/impl/browser/copy
import harness/impl/browser/paste
import lustre
import lustre/attribute as a
import lustre/element
import lustre/element/html as h
import lustre/event
import morph/editable as e

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

fn render(state) {
  let src =
    e.Block(
      [#(e.Bind("message"), e.Call(e.Perform("Copy"), [e.String("Go")]))],
      e.Vacant(""),
      True,
    )
  h.div([a.class("yellow-gradient")], [
    components.header(),
    h.div([a.class("mx-auto max-w-2xl")], [
      snippet.render(snippet.init(src, effects())),
      p("hello"),
      p(
        "EYG has controlled effects this means any program can be inspected to see what it needs from the environment it runs in.
      For example these snippets have an alert effect",
      ),
      p("There are hashes that allow reproducable everything"),
    ]),
  ])
}

fn effects() {
  [
    #(alert.l, #(alert.lift, alert.reply, alert.blocking)),
    #(copy.l, #(copy.lift, copy.reply(), copy.blocking)),
    #(paste.l, #(paste.lift, paste.reply(), paste.blocking)),
  ]
}
