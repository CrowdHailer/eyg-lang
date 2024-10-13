import eyg/website/components
import eyg/website/components/snippet
import eyg/website/home/state
import eyg/website/page
import gleam/list
import gleam/option.{None}
import lustre
import lustre/attribute as a
import lustre/element
import lustre/element/html as h

pub fn page(bundle) {
  page.app(None, "eyg/website/home", "client", bundle)
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

fn feature(title, description, last, item, reverse) {
  h.div(
    [
      a.class("mx-auto w-full max-w-6xl my-28 px-8 gap-12 hstack"),
      a.classes([#("flex-row-reverse", reverse)]),
    ],
    [
      h.div([a.style([#("flex", "0 1 40%")])], [
        h.h2([a.class("text-4xl my-8 font-bold")], [element.text(title)]),
        ..list.map(description, fn(d) {
          h.div([a.class("my-2 text-lg")], [element.text(d)])
        })
        |> list.append([last])
        // h.div([a.class("my-2 text-lg")], [
      //   element.text(
      //     "The effects that any piece of a program might need can be deduced ahead of running it.",
      //   ),
      // ]),
      // h.div(
      //   [a.class("py-2 px-6 rounded-xl bg-green-100 inline-block my-4 text-xl")],
      //   [element.text("find out more")],
      // ),
      ]),
      h.div([a.style([#("flex", "0 1 60%")])], item),
    ],
  )
}

fn caption(text) {
  h.div([a.class("text-center font-bold text-gray-400")], [element.text(text)])
}

type Merit {
  Predictable
  Useful
  Confident
}

fn merit_colour(merit) {
  case merit {
    Predictable -> "green-100"
    Useful -> "pink-100"
    Confident -> "red-100"
  }
}

fn action(text, merit) {
  h.div(
    [
      a.class(
        "py-2 px-6 rounded-xl bg-"
        <> merit_colour(merit)
        <> " inline-block my-4 text-xl font-bold",
      ),
    ],
    [element.text(text)],
  )
}

fn render(s) {
  h.div([a.class("")], [
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
    feature(
      "Edit with confidence",
      [
        "Edit your programs directly. Instead of carefully adjusting text the EYG editor allows you to confidently make structural changes to your program.",
        "Never miss a bracket or semi-colon again.",
      ],
      action("Watch the full guide", Confident),
      [h.div([a.class("cover bg-red-100")], [element.text("Video")])],
      True,
    ),
    feature(
      "Never crash",
      [
        "Guarantee that a program will never crash by checking it ahead of time.
        EYG can check that you program is sound without the need to add any type annotations.",
        "EYG's type system builds upon a proven mathmatical foundation by using row typing.",
        // "Row types ensure consistency in your programs use of Records, Unions and effects.",
      ],
      element.none(),
      [
        snippet(s, state.type_check_key),
        caption("Click on error message to jump to error."),
      ],
      False,
    ),
    feature(
      "Run anywhere",
      [
        "EYG programs are all independent of the machine they run on.
        There is no difference for Mac or Windows or standard access to ",
        "Any runtime can make an effect available, For example this tweet effect",
      ],
      action("Read more about the effects", Useful),
      [snippet(s, state.twitter_key)],
      True,
    ),
    feature(
      "Manage side effects",
      [
        "Any interaction with the world outside your program is accomplished via an Effect.",
        "The effects that any piece of a program might need can be deduced ahead of running it.",
        "Testing is always the same",
      ],
      action("Read the effects documentation.", Predictable),
      [
        snippet(s, state.predictable_effects_key),
        caption("Click above to run and edit."),
      ],
      False,
    ),
    feature(
      "Immutable references",
      [
        "Every program, script or function has unique reference.",
        "In EYG all packages and dependencies are fetched by reference, ensuring the same code is fetched everytime.",
      ],
      action("Read the reference documentation.", Predictable),
      [snippet(s, state.fetch_key)],
      True,
    ),
    feature(
      "Cross boundaries",
      [
        "Closure serialisation allows functions to be efficiently transformed back into source code and sent to other machines.",
      ],
      h.div(
        [a.class("py-2 px-6 rounded-xl bg-pink-100 inline-block my-4 text-xl")],
        [element.text("find out more")],
      ),
      [snippet(s, state.closure_serialization_key)],
      False,
    ),
    feature(
      "Hot code reloading",
      [
        "Use EYG's structural type system to validate that updates will work ahead of time",
        "More information coming soon.",
      ],
      h.div(
        [a.class("py-2 px-6 rounded-xl bg-pink-100 inline-block my-4 text-xl")],
        [element.text("find out more")],
      ),
      [
        // snippet(s, state.)
      ],
      True,
    ),
    feature(
      "Iterate fast with a shell",
      ["Coming soon."],
      h.div(
        [a.class("py-2 px-6 rounded-xl bg-pink-100 inline-block my-4 text-xl")],
        [element.text("find out more")],
      ),
      [
        // snippet(s, state.)
      ],
      False,
    ),
    feature(
      "Runtimes",
      ["Coming soon."],
      h.div(
        [a.class("py-2 px-6 rounded-xl bg-pink-100 inline-block my-4 text-xl")],
        [element.text("find out more")],
      ),
      [
        // snippet(s, state.)
      ],
      True,
    ),
    h.div([a.class("bg-green-100 vstack h-1/2")], [
      h.div([a.class("max-w-3xl mx-auto hstack")], [
        h.script(
          [
            a.attribute("data-form", "b3a478b8-39e2-11ef-97b9-955caf3f5f36"),
            a.src(
              "https://eocampaign1.com/form/b3a478b8-39e2-11ef-97b9-955caf3f5f36.js",
            ),
            a.attribute("async", ""),
          ],
          "",
        ),
      ]),
      // h.div([], [element.text("github")]),
    // h.div([a.class("expand")], [element.text("newsletter")]),
    ]),
    // section("Closure serialisation", [
  //   snippet(s, state.closure_serialization_key),
  //   p(
  //     "Closure serialisation allows functions to be efficiently transformed back into source code and sent to other machines.",
  //   ),
  //   // p("hello"),
  // // p(
  // //   "EYG has controlled effects this means any program can be inspected to see what it needs from the environment it runs in.
  // // For example these snippets have an alert effect",
  // // ),
  // // p("Download is an even better effect in the browser"),
  // // p("There are hashes that allow reproducable everything"),
  // ]),
  // section("run everywhere", [
  //   snippet(s, state.),
  //   p("Integrate into services"),
  // ]),
  // section("Immutable references", [
  //   snippet(s, state.),
  //   p(
  //     "All declarations can be uniquely hashed and referenced from other code.",
  //   ),
  //   p(
  //     "Once a dependency is fixed it can never change because changing the hash would update your program's hash.",
  //   ),
  // ]),
  // section("Immutable references", [snippet(s, state.hash_key)]),
  ])
}
