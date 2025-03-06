import gleam/list
import gleam/option.{None}
import gleam/string
import gleam/time/calendar.{Date}
import gleroglero/outline
import jot
import lustre/attribute as a
import lustre/element
import lustre/element/html as h
import mysig/asset
import mysig/html
import website/components
import website/components/clock
import website/components/typeset as t
import website/routes/common
import website/routes/news/edition

fn layout(body) {
  use layout <- asset.do(asset.load("src/website/routes/layout.css"))
  use neo <- asset.do(asset.load("src/website/routes/neo.css"))
  html.doc(
    list.flatten([
      [
        html.stylesheet(html.tailwind_2_2_11),
        html.stylesheet(asset.src(layout)),
        html.stylesheet(asset.src(neo)),
        html.plausible("eyg.run"),
      ],
      common.page_meta(
        "/roadmap",
        "Development roadmap for EYG language",
        "A list of the major enchancements being added to the EYG programming language.",
      ),
    ]),
    body,
  )
  |> asset.done()
}

fn p(content) {
  h.p([a.class("mx-auto w-full max-w-3xl my-2 px-1")], edition.inline(content))
}

fn escape_id(text) {
  text
  |> string.lowercase
  |> string.replace(" ", "-")
}

fn body() {
  [
    components.header(fn(_) { todo }, None),
    h.div(
      [a.class("bg-gradient-to-bl from-green-100 pt-14 pb-1 to-green-200")],
      [
        h.h1([a.class("mx-auto w-full max-w-3xl text-3xl my-4 px-1")], [
          element.text("Roadmap"),
        ]),
        p([
          t.text("A list of the major enchancements being added to EYG. "),
          // It's a scripting language buuuut general purpose
          //   t.text(
          //     "There is much to do to make programming accessible confident activity for many more people.",
          //   ),
          //   // t.emphasis("Dooo"),
          // // t.strong("Dooo"),
          t.text("The number one goal is to increase "),
          t.strong("feedback"),
          t.text(" so priorities will be reordered to help with that."),
        ]),
      ],
    ),
    // h.div([], [element.text("editor packages AST Runtime")]),
    h.main(
      [],
      list.map(content(), fn(item) {
        case item {
          Feature(id, title, description, done, status) -> {
            [
              h.h2(
                [
                  a.class("mt-6 px-1 mb-2 flex items-center gap-2 relative"),
                  a.id(escape_id(id)),
                ],
                [
                  h.a(
                    [
                      a.class(
                        "-left-6 absolute hover:opacity-100 opacity-30 w-4",
                      ),
                      a.href("#" <> escape_id(id)),
                    ],
                    [outline.link()],
                  ),
                  h.span([a.class("text-xl font-bold")], [element.text(title)]),
                  status_badge(status),
                ],
              ),
              ..list.map(
                {
                  description |> list.append([[t.strong("Done when " <> done)]])
                },
                p,
              )
            ]
            |> h.div([a.class("mx-auto w-full max-w-3xl")], _)
          }
        }
      }),
    ),
    components.footer(),
  ]
}

fn badge(class, message) {
  h.span([a.class("p-1 rounded whitespace-nowrap text-sm " <> class)], [
    element.text(message),
  ])
}

fn project_commit_link(hash, content) {
  let url = "https://github.com/CrowdHailer/eyg-lang/commit/" <> hash
  h.a([a.href(url), a.target("_blank")], content)
}

fn vimeo_text_link(text, id) {
  jot.Link([jot.Text(text)], jot.Url("https://vimeo.com" <> id))
}

fn website_text_link(text, id) {
  jot.Link([jot.Text(text)], jot.Url("https://eyg.run" <> id))
}

fn status_badge(status) {
  case status {
    Pending -> badge("bg-blue-700 text-blue-200", "Pending")
    InProgress -> badge("bg-gray-700 text-gray-100", "In progress")
    Delivered(date, commit) ->
      project_commit_link(commit, [
        badge("bg-green-3", "Delivered " <> clock.date_to_string(date)),
      ])
  }
}

pub type Status {
  // Proposed
  // Exploration
  // Blocked empty list of ready
  Pending
  InProgress
  // Closed(note: Inline) in favour of others
  // date could be pulled from the commit 
  Delivered(date: calendar.Date, commit: String)
}

pub type Item {
  Feature(
    id: String,
    title: String,
    description: List(List(jot.Inline)),
    done: String,
    delivered: Status,
  )
  // Task vs feature?
  // Talk(date: String, video: Option(String), slides: Option(String))
}

// align with midas provision of social posts. have a shared tweet

// Can have a check that all links are resolvable and not localhost.
fn content() {
  [
    Feature(
      "embeddable-code-snippets",
      "Embeddable code snippets",
      [
        [
          t.text("The "),
          vimeo_text_link("editor snippets", "1033086983"),
          t.text(
            " on the EYG homepage and in the documentation page can be edited and executed.",
          ),
          t.text(
            "This is very helpful when explaining concepts as they can immediately be played with.",
          ),
        ],
        [
          t.text(
            "The snippets are Lustre components and can only be used in Lustre apps.",
          ),
          t.text(
            "I want all features of EYG, the language and runtime, to be widely available.",
          ),
          t.text(
            "Therefore it should be possible to use the same style of code snippet in other webpages.",
          ),
        ],
      ],
      "an interactive snippet can be embedded in any HTML using a script tag.",
      Delivered(
        Date(2025, calendar.January, 23),
        "a6c2eef5972bf27c0f51587767e573b2ca2450bd",
      ),
    ),
    Feature(
      "example-code-in-the-shell",
      "Example code in the shell",
      [
        [
          t.text(
            "To help users get started have a selection of examples that can be loaded into the shell.",
          ),
        ],
        [
          t.text("This previously existed in an earlier iteration of "),
          vimeo_text_link("the shell", "997719570"),
          t.text("."),
        ],
      ],
      "when a selection of code examples are presented in the empty shell.",
      Delivered(
        Date(2025, calendar.January, 14),
        "c1fcb6736de419898040c2d6da5890245b713267",
      ),
    ),
    Feature(
      "stable-ast-format",
      "Stable AST format",
      [
        [
          t.text(
            // TODO link to current AST
            "The Abstract Syntax Tree (AST) has been effectively stable for a long time, only small changes to the set of builtin functions have happened.",
          ),
        ],
        [
          t.text(
            "A goal of EYG is that any program will continue to work indefinitely.",
          ),
          t.text(
            "This promise requires that all changes to the AST are conducted in a backwards compatible way.",
          ),
        ],
        [
          t.text(
            "The shallow effect handler will be removed to have only a single kind of effect handler in the AST.",
          ),
          t.text(
            "Currently deep and shallow handlers are supported only because of previous exploratory work.",
          ),
          t.text(
            "A stable encoding of the AST is required to give stable hash references",
          ),
        ],
      ],
      "all programs are saved with a version identifier for the format.",
      Pending,
    ),
    Feature(
      "oss-license-decision",
      "Open source license decision",
      [
        [
          t.text(
            "The whole EYG project is currently unlicensed, this needs to change to enable contributions which have already been submitted.",
          ),
        ],
        [
          t.text(
            "The reason to not use a fully open license is to protect the process of name resolution.",
          ),
          t.text(
            "This is because I want EYG to be embedded in lots of places and behave the same way, including named reference lookup.",
          ),
          t.text("i.e. "),
          t.code("@bank"),
          t.text(
            " should always point to the same code otherwise it's a security risk for users.",
          ),
          t.text("Other than that I intend for everything to be available."),
        ],
        [
          t.text(
            "I should consider if different parts of the project need different licensing, but I would like to avoid that.",
          ),
        ],
      ],
      "all repos have a license file.",
      Pending,
    ),
    Feature(
      "stable-content-address-for-expressions",
      "Stable content address for expressions",
      [
        [
          t.text("Code can be referenced by name (@) or hash (#)."),
          t.text(
            "EYG source is saved as JSON which means that the hash is not stable.",
          ),
          t.text(
            "This is not currently an issue because published code is stored immutably in the database with the hash acting as an opaque identifier.",
          ),
        ],
        [
          t.text(
            "To use the hash as a checksum and enable signing of package publishing the hash format needs to be stable.",
          ),
        ],
        [
          t.text("Use "),
          t.link("DAG-JSON", "https://ipld.io/docs/codecs/known/dag-json/"),
          t.text(" as the storage and hashing format for the AST."),
        ],
        [
          t.text("This format enables storing EYG code on "),
          t.link("IPFS", "https://ipfs.tech/"),
          t.text(
            " and building towards a decentralised package management solution.",
          ),
        ],
      ],
      "hashing is deterministic for a given expression.",
      Pending,
    ),
    Feature(
      "editor-for-large-programs",
      "Editor for large programs",
      [
        [
          t.text("The "),
          website_text_link("current editor", "/editor"),
          t.text(" is also a shell."),
          t.text(
            "It is optimised for quickly writing and running small programs.",
          ),
        ],
        [
          t.text(
            "There should be an editing environment optimised for creating and subsequently modifying larger programs.",
          ),
          t.text("several of the "),
          t.link("early iterations", "https://petersaxton.uk/log/"),
          t.text(
            " were optimised for this kind of editing but not built on the latest structural edit library code",
          ),
        ],
        [
          t.text(
            "This environment would use more screen for the code and make collapsing/expanding code easy to focus within a large program.",
          ),
          t.text(
            "Saving and loading code from a host computer would be supported, instead of relying on the current approach of copy/paste.",
          ),
          t.text(
            "It would not have the ability to run any effectful code and would not keep a history of code runs.",
          ),
          t.emphasis(
            "Running pure code might still be useful for integration with tests or similar.",
          ),
        ],
        [],
      ],
      "loading, editing and saving larger programs is easy.",
      Pending,
    ),
    Feature(
      "sign-package-release",
      "Sign package release",
      [
        [
          t.text(
            "There should be a way for consumers to receive updates to their dependencies without relying on the authority of EYG.",
          ),
          t.text(
            "This is foundational for building resiliance to supply-chain attack.",
          ),
        ],
        [
          t.text(
            "Users register keys to their account which they use for signing package releases.",
          ),
          t.text(
            "EYG will centrally validate that all new releases are signed with a valid user key.",
          ),
          t.text(
            "A consumer application will be able to verify all releases have a valid signature.",
          ),
        ],
      ],
      "all new relases have signatures validated against account public keys.",
      Pending,
    ),
    Feature(
      "generalised-effects-in-single-function",
      "Generalised effects in single function",
      [
        [
          t.text(
            "External effects currently unify to the same type, when used in the same function.",
          ),
          t.text("This behaviour is too constrained for some effects."),
          t.text("For example the "),
          t.code("Abort"),
          t.text(
            " effect does not resume and so it's reply type should remain generalised across use in a single function.",
          ),
        ],
        [
          t.text(
            "This unification behaviour would allow all builtins to be replaced with effects.",
          ),
          t.text(
            "Moving builtins to effects would allow checking to see if a program uses them and remove them from the compiled artifact if not.",
          ),
          t.text("Removing the builtins should be a separate task."),
        ],
      ],
      "effects that do not resume can remain general in the same function.",
      Pending,
    ),
    Feature(
      "structural-code-diffs",
      "Structural code diffs",
      [
        [
          t.text(
            "There is currently no way to see diffs between two EYG expressions.",
          ),
          t.text(
            "Providing a diff is a quality of life improvement that will become more important as programs grow.",
          ),
        ],
        [
          t.text(
            "Tree diffing is a solved problem, however there are choices to be made around presentation of the diffs.",
          ),
          t.text("The"),
          t.link("Difftastic project", "https://difftastic.wilfred.me.uk/"),
          t.text(" is a good inspiration for how this can look."),
        ],
      ],
      "when two expressions can visually be compared.",
      Pending,
    ),
    Feature(
      "collapsible-value-components",
      "Collapsible value components.",
      //  better errors
      [
        [
          t.text("All values are printed in the same way."),
          t.text(
            "Large values are truncated which makes working with them difficult",
          ),
        ],
        [
          t.text(
            "The browser is a rich environment that can be utilised for creating interactive views on values.",
          ),
          t.text(
            "For inspiration here consider how large objects are printed in the JavaScript console.",
          ),
        ],
      ],
      "large runtime values can be rendered and a user can interact with them.",
      Pending,
    ),
    // Feature(
    //   "Compact format for saving programs",
    //   [
    //     [
    //       t.text(
    //         "A more space efficient for saved EYG programs.
    // This would reduce storage requirements allowing more packages to be stored and indexed in the client.
    // It would also requce the size of downloads uploads when transmitting programs.

    // The current storage format is JSON which is inefficent in terms of storage and load/parse.",
    //       ),
    //     ],
    //   ],
    //   Pending,
    // ),

    Feature(
      "native-runtime",
      "Native runtime",
      [
        [
          t.text(
            "The current interpreter is implemented in JavaScript and can used in the shell using the",
          ),
          t.link("npm package", "https://www.npmjs.com/package/eyg-run"),
          t.text("."),
        ],
        [
          t.text(
            "writing a native interpreter that could be used to build an installable binary would make use in the shell easier.",
          ),
        ],
        [
          t.text("A native version should also improve performance."),
          t.text(
            "A language with good WASM support should be picked so that the performance improvement can also be leveraged in the web environment.",
          ),
          t.text(
            "I know Rust is sufficient for the job from working on the Gleam compiler that is fast and can run in the browser via a WASM build.",
          ),
          t.text("The interpreter is a small program and Zig is "),
          t.link(
            "an interesting option.",
            "https://zackoverflow.dev/writing/unsafe-rust-vs-zig/",
          ),
        ],
      ],
      "a single binary can be installed to run EYG programs.",
      Pending,
      // prerequisit - build on compact format
    ),
    Feature(
      "property-test-editor-navigation",
      "Property test editor navigation",
      [
        [
          t.text(
            "Write tests to ensure that in all cases navigation is consistent.",
          ),
        ],
        [
          t.text("The behaviour of the editor is already understood:"),
          t.text(
            "Left then right navigation should always return to the same node if on a leaf node.",
          ),
          t.text(
            "Left or right navigation should go to a child if starting on a non-leaf node.",
          ),
        ],
        [
          t.text(
            "Implementing property tests for these expectations would help handle the large number of edge cases.",
          ),
        ],
      ],
      "the listed navigation properties are tested.",
      Pending,
    ),
  ]
}

pub fn page() {
  use content <- asset.do(layout(body()))
  asset.done(element.to_document_string(content))
}
