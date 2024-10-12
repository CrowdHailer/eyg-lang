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
  h.div(
    [
      a.style([
        // #("min-height", "100vh")
      ]),
      a.class("vstack"),
    ],
    content,
  )
}

fn render(s) {
  h.div([a.class("yell-gradient")], [
    page_area([
      // components.header(),
      h.div([a.class("expand hstack")], [
        h.div([a.class("m-2")], [
          h.p([a.class("text-4xl font-bold")], [element.text("EYG")]),
          h.p([a.class("max-w-lg text-2xl")], [
            element.text(
              "The stable foundation for software that runs forever.",
            ),
          ]),
          h.div([a.class("flex gap-2 mt-4")], [
            h.a(
              [
                a.href("/editor"),
                a.class(
                  "inline-block py-2 px-3 rounded-xl text-white font-bold bg-gray-900 border-2 border-gray-900",
                ),
              ],
              [element.text("Editor")],
            ),
            h.a(
              [
                a.href("/documentation"),
                a.class(
                  "border-2 border-black font-bold inline-block py-2 px-3 rounded-xl",
                ),
              ],
              [element.text("Documentation")],
            ),
          ]),
          // h.p([], [
        //   h.span([a.class("font-bold")], [element.text("Predictable:")]),
        //   element.text(
        //     " programs are deterministic, dependencies are immutable",
        //   ),
        // ]),
        // h.p([], [
        //   h.span([a.class("font-bold")], [element.text("Useful:")]),
        //   element.text(
        //     " run anywhere, managed effects allow programs to declare runtime requirements",
        //   ),
        // ]),
        // h.p([], [
        //   h.span([a.class("font-bold")], [element.text("Confident:")]),
        //   element.text(
        //     " A sound structural type system guarantees programs never crash",
        //   ),
        // ]),
        ]),
        h.p([a.class("-mr-24 text-8xl")], [
          // element.text("EYG"),
          h.img([
            a.class("w-full max-w-xl"),
            a.src("https://eyg.run/assets/pea.webp"),
            // a.style([
          //   #("width", "500px"),
          //   #("height", "500px"),
          //   // #("vertical-align", "bottom"),
          // // #("margin-bottom", "-10px"),
          // // #("margin-top", "-10px"),
          // ]),
          ]),
        ]),
      ]),
    ]),
    h.div([a.class("hstack mx-auto gap-10")], [
      h.p(
        [
          a.class(
            "w-56 h-56 p-6 flex flex-col py-12 rounded-lg bg-green-100 neo-2xl",
          ),
        ],
        [
          h.div([a.class(" text-xl font-bold")], [element.text("Predictable:")]),
          element.text(
            " programs are deterministic, dependencies are immutable",
          ),
        ],
      ),
      h.p(
        [
          a.class(
            "w-56 h-56 p-6 flex flex-col py-12 rounded-lg bg-pink-100 neo-2xl",
          ),
        ],
        [
          h.div([a.class(" text-xl font-bold")], [element.text("Useful:")]),
          element.text(
            " run anywhere, managed effects allow programs to declare runtime requirements",
          ),
        ],
      ),
      h.p(
        [
          a.class(
            "w-56 h-56 p-6 flex flex-col py-12 rounded-lg bg-red-100 neo-2xl",
          ),
        ],
        [
          h.div([a.class(" text-xl font-bold")], [element.text("Confident:")]),
          element.text(
            " A sound structural type system guarantees programs never crash",
          ),
        ],
      ),
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
