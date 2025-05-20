import gleam/list
import lustre
import lustre/attribute as a
import lustre/element
import lustre/element/html as h
import mysig/asset
import mysig/asset/client
import mysig/html
import website/components
import website/components/auth_panel
import website/components/example/view
import website/components/reload
import website/config
import website/harness/spotless.{Config}
import website/routes/common
import website/routes/home/state

// TODO this can return just some code id needs to match in client and empty_lustre
// without layout it can move to common
pub fn app(module, func) {
  use script <- asset.do(asset.bundle(module, func))
  use ssr <- asset.do(view())
  let config = Config(dnsimple_local: True, twitter_local: True)
  let #(state, _eff) = state.init(#(config, auth_panel.in_memory_store()))

  layout([
    h.div([a.id("app")], [ssr(state)]),
    h.script([a.src(asset.src(script))], ""),
  ])
}

fn layout(body) {
  use layout <- asset.do(asset.load("src/website/routes/layout.css"))
  use neo <- asset.do(asset.load("src/website/routes/neo.css"))
  html.doc(
    list.flatten([
      [
        html.stylesheet(html.tailwind_2_2_11),
        html.stylesheet(asset.src(layout)),
        html.stylesheet(asset.src(neo)),
        common.prism_style(),
      ],
      common.page_meta(
        "/",
        "EYG",
        "EYG is a programming language for predictable, useful and most of all confident development.",
      ),
      common.diagnostics(),
    ]),
    body,
  )
  |> asset.done()
}

pub fn page() {
  use content <- asset.do(app("website/routes/home", "client"))
  asset.done(element.to_document_string(content))
}

// client has to be a top level function for bundling
pub fn client() {
  let assert Ok(render) = client.load_manifest(view())
  let app = lustre.application(state.init, state.update, render)
  let assert Ok(_) =
    lustre.start(app, "#app", #(config.load(), auth_panel.in_memory_store()))
  Nil
}

pub fn snippet(state: state.State, i) {
  // let failure = case state.active {
  //   state.Editing(key, failure) if i == key -> failure
  //   _ -> None
  // }
  case state.get_example(state, i) {
    state.Simple(example) ->
      view.render(example) |> element.map(state.SimpleMessage(i, _))
    state.Reload(example) ->
      reload.render(example) |> element.map(state.ReloadMessage(i, _))
  }
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
      a.class("mx-auto w-full max-w-6xl my-28 px-1 md:px-8 gap-12 md:flex"),
      a.style([#("align-items", "center")]),
      a.classes([#("flex-row-reverse", reverse)]),
    ],
    [
      h.div([a.style([#("width", "40%")])], [
        h.h2([a.class("text-4xl my-8 font-bold")], [element.text(title)]),
        ..list.map(description, fn(d) {
          h.div([a.class("my-2 text-lg")], [element.text(d)])
        })
        |> list.append([last])
      ]),
      h.div([a.class(""), a.style([#("width", "60%")])], item),
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

fn view() {
  use penelopea <- asset.do(asset.load("src/website/images/pea.webp"))
  fn(s: state.State) {
    h.div([a.class("")], [
      case s.auth.active {
        True -> auth_panel.render(s.auth) |> element.map(state.AuthMessage)
        False -> element.none()
      },
      components.header(state.AuthMessage, s.auth.session),
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
          snippet(s, state.type_check_key),
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
        [snippet(s, state.twitter_key)],
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
          snippet(s, state.predictable_effects_key),
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
        [snippet(s, state.fetch_key)],
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
        [snippet(s, state.closure_serialization_key)],
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
        [snippet(s, state.hot_reload_key)],
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
