import gleam/dict
import gleam/list
import gleam/option.{type Option, None}
import gleam/string
import jot
import lustre/attribute as a
import lustre/element
import lustre/element/html as h
import mysig/asset
import mysig/html
import website/components
import website/components/typeset as t
import website/routes/common
import website/routes/documentation
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
        "/",
        "EYG",
        "EYG is a programming language for predictable, useful and most of all confident development.",
      ),
    ]),
    body,
  )
  |> asset.done()
}

fn p(content) {
  h.p([a.class("mx-auto w-full max-w-3xl my-2")], edition.inline(content))
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
        h.h1([a.class("mx-auto w-full max-w-3xl text-3xl my-4")], [
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
          Feature(id, title, description, status) -> {
            [
              h.h2(
                [
                  a.class("mt-6 mb-2 flex items-center gap-2"),
                  a.id(escape_id(id)),
                ],
                [
                  h.span([a.class("text-xl font-bold")], [element.text(title)]),
                  status_badge(status),
                ],
              ),
              ..list.map(description, p)
            ]
            |> h.div([a.class("mx-auto w-full max-w-3xl")], _)
          }
          _ -> todo
        }
      }),
    ),
    components.footer(),
  ]
}

fn badge(class, message) {
  h.span([a.class("p-1 rounded text-sm " <> class)], [element.text(message)])
}

fn status_badge(status) {
  case status {
    Pending -> badge("bg-blue-700 text-blue-200", "Pending")
    InProgress -> badge("bg-gray-700 text-gray-100", "In progress")
    Delivered(_, _) -> badge("bg-green-3", "Delivered")
  }
}

pub type Status {
  // Proposed
  // Exploration
  // Blocked empty list of ready
  Pending
  InProgress
  // Closed(note: Inline) in favour of others
  // TODO have better time
  Delivered(date: String, commit: String)
}

pub type Item {
  Feature(
    id: String,
    title: String,
    description: List(List(jot.Inline)),
    delivered: Status,
  )
  // Task vs feature?
  Talk(date: String, video: Option(String), slides: Option(String))
}

// align with midas provision of social posts. have a shared tweet
// TODO linkable so it can be share posted

// Can have a check that all links are resolvable and not localhost.
fn content() {
  [
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
          t.text(
            "This previously existed in an earlier iteration of the shell.",
          ),
          // TODO link
        ],
      ],
      // TODO real date
      Delivered("", ""),
    ),
    Feature(
      "stable-ast-format",
      "Stable AST format",
      [
        [
          t.text(
            // TODO link to current AST
            "The Abstract Syntax Tree (AST) has been effectivly stable for a long time, only small changes to the set of builtin functions have happen.",
          ),
        ],
        [
          t.text(
            "A goal of EYG is any programs will continue to work indefinetly.",
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
            "Currently deep and shallow handlers are supported only because of previous exploritory work.",
          ),
          t.text(
            "A stable encoding of the AST is required to give stable hash references",
          ),
        ],
        [
          t.strong(
            "Done when all programs are saved with a version identifier for the format.",
          ),
        ],
        // [
      //   t.text(" Most changes have been in builtins"),
      // ],
      ],
      Pending,
    ),
    Feature(
      "oss-license",
      "Open source license descision",
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
        [t.strong("Done when all repos have a license file.")],
      ],
      Pending,
    ),
    // License
  // Feature(
  //   "",
  //   "Module editor",
  //   [
  //     [
  //       t.text(
  //         "This will improve the experience of writing larger programs.

  // The shell [editor]() is optimised for rapidly writing and running small programs,
  // A module editor would optimise for iterating on a larger program.
  // The current understanding is that modules would be pure.
  // Effectual functions in a module would execute in a shell or production environment.",
  //       ),
  //     ],
  //   ],
  //   Pending,
  // ),
  // Feature(
  //   "Expandable value components.",
  //   [
  //     [
  //       t.text(
  //         "This will improve the experience of working with large runtime values.

  //   This task is only for values but similar components should exist for types and effects",
  //       ),
  //     ],
  //   ],
  //   Pending,
  // ),
  // Feature(
  //   "Merge concurrent edits.",
  //   [
  //     [
  //       t.text(
  //         "Currently if there are concurrent edits resolution is based on a last writer wins.

  //   If a text editor is made available in the web then this could be build on automerge TODO make a link. or other existing CRDT.
  //   A more powerful solution would be to merge the AST.
  //   This would support concurrent changes using the structural editor, as well as text editor if that comes to exist.

  //   Fixing this will enable further collaboration usecases.",
  //       ),
  //     ],
  //   ],
  //   Pending,
  // ),
  // Feature(
  //   "Back up code to a users account.",
  //   [
  //     [
  //       t.text(
  //         "For a logged in user their code snippets should be automatically backed up.",
  //       ),
  //     ],
  //   ],
  //   Pending,
  // ),
  // Feature(
  //   "Save to file from editor",
  //   [
  //     [
  //       t.text(
  //         "Make it easier for a user to store a whole program on their computer.

  //   It is already possible to copy/paste the structural format to a users computer but the experience is cumbersome and therefore error prone.
  //   As mobile makes file systems harder to access this feature is a lower priority than saving to a users account automatically once logged in.",
  //       ),
  //     ],
  //   ],
  //   Pending,
  // ),
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
  // Feature(
  //   "Sign package releases.",
  //   [
  //     [
  //       t.text(
  //         "Users should be able to register keys to their account and the EYG hub validates all new releases are signed with a valid user key.

  //   This is foundational for building resiliance to supply chain attack.",
  //       ),
  //     ],
  //   ],
  //   Pending,
  // ),
  // Feature(
  //   "Fast and native runtime",
  //   [
  //     [
  //       t.text(
  //         "The current interpreter is implemented in JavaScript.
  //   Writing a native interpreter would make it easier to use EYG from a users shell, this is already possible using node (Link to npm)
  //   However implementing a native version would improve performance.

  //   A language with good WASM support should be picked so that the performance improvement can also be leveraged in the web environment.
  //   I know Rust is sufficient for the job from working on the Gleam compiler that is fast and can run in the browser via a WASM build.
  //   However the interpreter should be a small program and Zig is an option https://zackoverflow.dev/writing/unsafe-rust-vs-zig/",
  //       ),
  //     ],
  //   ],
  //   Pending,
  //   // prerequisit - build on compact format
  // ),

  // Feature(
  //   "consistent navigation property tests.",
  //   [
  //     [
  //       t.text(
  //         "Ensure that in all cases navigation is consistent.

  //   The behaviour of the editor is already understood:
  //   - left then right navigation should always return to the same node if on a leaf node.
  //   - left or right navigation should go to a child if starting on a non-leaf node.

  //   Implementing property tests for these expectation would help handle the large number of edge cases.",
  //       ),
  //     ],
  //   ],
  //   Pending,
  // ),
  // Feature(
  //   "Polymorphic effects",
  //   [
  //     [
  //       t.text(
  //         "Allow effects to be generalized in the same context

  //   This will make effects like Abort more ergonomic.
  //   In the case of Abort the lifted type must be consistent but because the effect never resumes the reply type can be generalised.
  //   This enhancement would make effects functionally equivalent to builtins allowing us to simplify implementation by removing builtins",
  //       ),
  //     ],
  //   ],
  //   Pending,
  // ),
  ]
}

pub fn page() {
  use content <- asset.do(layout(body()))
  asset.done(element.to_document_string(content))
}
