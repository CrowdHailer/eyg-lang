import gleam/list
import lustre/attribute as a
import lustre/element
import lustre/element/html as h
import mysig/asset
import website/components
import website/routes/documentation/view as doc
import website/routes/home/examples
import website/routes/home/state

fn snippet(state: state.State, id) {
  let buffer = state.get_example(state, id)

  doc.render_example(
    buffer,
    state.mode,
    id,
    state.UserClickedCode(id, _),
    state.PickerMessage,
    state.InputMessage,
  )
}

fn page_area(content) {
  h.div(
    [
      a.styles([
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
      a.class("mx-auto w-full max-w-6xl my-28 px-1 md:px-8 gap-12 md:flex"),
      a.styles([#("align-items", "center")]),
      a.classes([#("flex-row-reverse", reverse)]),
    ],
    [
      h.div([a.styles([#("width", "40%")])], [
        h.h2([a.class("text-4xl my-8 font-bold")], [element.text(title)]),
        ..list.map(description, fn(d) {
          h.div([a.class("my-2 text-lg")], [element.text(d)])
        })
        |> list.append([last])
      ]),
      h.div([a.class(""), a.styles([#("width", "60%")])], item),
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

fn action(text, href, merit) {
  h.a(
    [
      a.href(href),
      a.class(
        "inline-block py-2 px-6 rounded-xl bg-"
        <> merit_colour(merit)
        <> " inline-block my-4 text-xl font-bold",
      ),
    ],
    [element.text(text)],
  )
}

pub fn view() {
  use penelopea <- asset.do(asset.load("src/website/images/pea.webp"))
  fn(s: state.State) {
    h.div([a.class("")], [
      components.header(),
      page_area([
        h.div([a.class("expand hstack")], [
          h.div([a.class("m-2")], [
            h.p([a.class("text-4xl font-bold")], [element.text("EYG")]),
            h.p([a.class("max-w-lg text-2xl")], [
              element.text(
                "A programming language for predictable, useful and confident development.",
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
          ]),
          h.p([a.class("")], [
            // element.text("EYG"),
            h.img([
              a.class("w-full max-w-xl"),
              a.src(asset.src(penelopea)),
              a.alt("Penelopea, EYG's mascot"),
              // a.styles([
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
      h.div(
        [a.class("grid grid-cols-3 max-w-2xl gap-1 md:gap-6 px-1 mx-auto")],
        [
          h.div(
            [
              a.class(
                "p-2 md:p-6 flex flex-col py-4 md:py-12 rounded-lg bg-green-100 neo-2xl",
              ),
            ],
            [
              h.div([a.class(" text-xl font-bold")], [
                element.text("Predictable:"),
              ]),
              h.p([], [
                element.text(
                  " programs are deterministic, dependencies are immutable",
                ),
              ]),
            ],
          ),
          h.div(
            [
              a.class(
                "p-2 md:p-6 flex flex-col py-4 md:py-12 rounded-lg bg-pink-100 neo-2xl",
              ),
            ],
            [
              h.div([a.class(" text-xl font-bold")], [element.text("Useful:")]),
              h.p([], [
                element.text(
                  " run anywhere, managed effects allow programs to declare runtime requirements",
                ),
              ]),
            ],
          ),
          h.div(
            [
              a.class(
                "p-2 md:p-6 flex flex-col py-4 md:py-12 rounded-lg bg-red-100 neo-2xl",
              ),
            ],
            [
              h.div([a.class(" text-xl font-bold")], [
                element.text("Confident:"),
              ]),
              h.p([], [
                element.text(
                  " A sound structural type system guarantees programs never crash",
                ),
              ]),
            ],
          ),
        ],
      ),
      // feature(
      //   "Edit with confidence",
      //   [
      //     "Edit your programs directly. Instead of carefully adjusting text the EYG editor allows you to confidently make structural changes to your program.",
      //     "Never miss a bracket or semi-colon again.",
      //   ],
      //   action("Watch the full guide", "#", Confident),
      //   [h.div([a.class("cover")], components.vimeo_intro())],
      //   True,
      // ),
      feature(
        "Never crash",
        [
          "Guarantee that a program will never crash by checking it ahead of time.
        EYG can check that your program is sound without the need to add any type annotations.",
          "EYG's type system builds upon a proven mathematical foundation by using row typing.",
          // "Row types ensure consistency in your program's use of Records, Unions and Effects.",
        ],
        element.none(),
        [
          snippet(s, examples.type_check_key),
          caption("Click on error message to jump to error."),
        ],
        False,
      ),
      feature(
        "Run anywhere",
        [
          "EYG programs are all independent of the machine they run on.
        Any interaction with the world outside your program is accomplished via an effect.",
          "A runtime can make an effect available. For example all snippets on this EYG homepage have access to this Tweet effect",
        ],
        action(
          "Read more about the effects",
          "/documentation#perform-effect",
          Useful,
        ),
        [snippet(s, examples.twitter_key)],
        True,
      ),
      feature(
        "Manage side effects",
        [
          "All interactions to the world outside a program are managed as effects.",
          "Any effect can be intercepted using a handler. This allows the response from the outside world to be replaced.",
          "Handling effects is great for testing; if all effects are handled then your program is deterministic. No more flakey tests.",
        ],
        action(
          "Read the effects documentation.",
          "/documentation#handle-effect",
          Confident,
        ),
        [
          snippet(s, examples.predictable_effects_key),
          caption("Click above to run and edit."),
        ],
        False,
      ),
      feature(
        // "Immutable references",
        // [
        //   "Every program, script or function has a unique reference.",
        //   "In EYG all packages and dependencies are fetched by reference, ensuring the same code is fetched everytime.",
        // ],
        "Named references",
        [
          "Use an ecosystem of helpful packages to work faster. Share code with anyone using your unique handle.",
          "Signing up for account names is in closed beta for now. Get in touch to find out more",
        ],
        action(
          "Read the reference documentation.",
          "/documentation#references",
          Predictable,
        ),
        [snippet(s, examples.fetch_key)],
        True,
      ),
      feature(
        "Cross boundaries",
        [
          "Closure serialisation allows functions to be efficiently transformed back into source code and sent to other machines.",
          "Build client and server as a single strongly typed program. Even extend type guarantees over your build scripts.",
          "Other languages have the possiblity of closure serialisation, but EYG's runtime is designed to make them efficient.",
        ],
        action("Read the documentation.", "/documentation", Useful),
        [snippet(s, examples.closure_serialization_key)],
        False,
      ),
      feature(
        "Hot code reloading",
        [
          "Use EYG's structural type system to validate that updates will work ahead of time",
          "In this example you can increment the counter by clicking the rendered app.
        If you change the code the behaviour will update immediatly if safe.
        If the code changes modify the type then you will be asked for a migrate function.",
        ],
        action(
          "Stay up to date join the mailing list.",
          "#" <> components.signup,
          Confident,
        ),
        [snippet(s, examples.hot_reload_key)],
        True,
      ),
      feature(
        "Iterate fast with a shell",
        [
          "EYG already has a prototyped strongly typed shell environment.",
          "We need to get it ready and bring it to you.",
        ],
        action(
          "Stay up to date join the mailing list.",
          "#" <> components.signup,
          Useful,
        ),
        [],
        False,
      ),
      feature(
        "An ecosystem of runtimes",
        [
          "EYG is built to support multiple runtimes. You have already seen this with closure serialisation",
          "In the future EYG will be available in many more places, e.g. arduino, CLI's and IPaaS.",
          "EYG makes this easy by having a carefully designed minimal AST.",
        ],
        action(
          "Stay up to date join the mailing list.",
          "#" <> components.signup,
          Confident,
        ),
        [],
        True,
      ),
      components.footer(),
    ])
  }
  |> asset.done()
}
