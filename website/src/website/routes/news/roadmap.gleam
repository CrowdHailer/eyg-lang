import gleam/dict
import gleam/list
import gleam/option.{type Option, None}
import jot
import lustre/element
import lustre/element/html as h
import mysig/asset
import mysig/html
import website/components
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
        "/",
        "EYG",
        "EYG is a programming language for predictable, useful and most of all confident development.",
      ),
    ]),
    body,
  )
  |> asset.done()
}

fn body() {
  [
    components.header(fn(_) { todo }, None),
    ..list.map(content(), fn(item) {
      case item {
        Feature(title, description, _) -> {
          let document = jot.parse(description)
          let jot.Document(content, _references) = document
          [
            edition.block(jot.Heading(dict.new(), 1, [jot.Text(title)])),
            ..list.map(content, edition.block)
          ]
          |> h.div([], _)
        }
        _ -> todo
      }
    })
  ]
}

pub type Item {
  Feature(title: String, description: String, delivered: Option(String))
  // Task vs feature?
  Talk(date: String, video: Option(String), slides: Option(String))
}

// TODO jot for paragraph in description
// align with midas provision of social posts.
// TODO linkable so it can be share posted

fn content() {
  [
    Feature(
      "Module editor",
      "This will improve the experience of writing larger programs.
    
    The shell editor is optimised for rapidly writing and running small programs,
    A module editor would optimise for iterating on a larger program.
    The current understanding is that modules would be pure.
    Effectual functions in a module would execute in a shell or production environment.",
      None,
    ),
    Feature(
      "Expandable value components.",
      "This will improve the experience of working with large runtime values.
      
      This task is only for values but similar components should exist for types and effects",
      None,
    ),
    Feature(
      "Merge concurrent edits.",
      "Currently if there are concurrent edits resolution is based on a last writer wins.
      
      If a text editor is made available in the web then this could be build on automerge TODO make a link. or other existing CRDT.
      A more powerful solution would be to merge the AST.
      This would support concurrent changes using the structural editor, as well as text editor if that comes to exist.

      Fixing this will enable further collaboration usecases.",
      None,
    ),
    Feature(
      "Back up code to a users account.",
      "For a logged in user their code snippets should be automatically backed up.",
      None,
    ),
    Feature(
      "Save to file from editor",
      "Make it easier for a user to store a whole program on their computer.
    
      It is already possible to copy/paste the structural format to a users computer but the experience is cumbersome and therefore error prone.
      As mobile makes file systems harder to access this feature is a lower priority than saving to a users account automatically once logged in.",
      None,
    ),
    Feature(
      "Compact format for saving programs",
      "A more space efficient for saved EYG programs.
    This would reduce storage requirements allowing more packages to be stored and indexed in the client.
    It would also requce the size of downloads uploads when transmitting programs.
    
    The current storage format is JSON which is inefficent in terms of storage and load/parse.",
      None,
    ),
    Feature(
      "Sign package releases.",
      "Users should be able to register keys to their account and the EYG hub validates all new releases are signed with a valid user key.
      
      This is foundational for building resiliance to supply chain attack.",
      None,
    ),
    Feature(
      "Fast and native runtime",
      "The current interpreter is implemented in JavaScript.
      Writing a native interpreter would make it easier to use EYG from a users shell, this is already possible using node (Link to npm)
      However implementing a native version would improve performance.
      
      A language with good WASM support should be picked so that the performance improvement can also be leveraged in the web environment.
      I know Rust is sufficient for the job from working on the Gleam compiler that is fast and can run in the browser via a WASM build.
      However the interpreter should be a small program and Zig is an option https://zackoverflow.dev/writing/unsafe-rust-vs-zig/",
      None,
      // prerequisit - build on compact format
    ),
    Feature(
      "Examples to load in the shell",
      "To help users get started have a selection of examples that can be loaded into the shell.
    
      This previously existed in an earlier iteration of the shell. LINK to Video",
      None,
    ),
    Feature(
      "consistent navigation property tests.",
      "Ensure that in all cases navigation is consistent.
    
      The behaviour of the editor is already understood:
      - left then right navigation should always return to the same node if on a leaf node.
      - left or right navigation should go to a child if starting on a non-leaf node.
    
      Implementing property tests for these expectation would help handle the large number of edge cases.",
      None,
    ),
    Feature(
      "Polymorphic effects",
      "Allow effects to be generalized in the same context
    
      This will make effects like Abort more ergonomic.
      In the case of Abort the lifted type must be consistent but because the effect never resumes the reply type can be generalised.
      This enhancement would make effects functionally equivalent to builtins allowing us to simplify implementation by removing builtins",
      None,
    ),
  ]
}

pub fn page() {
  use content <- asset.do(layout(body()))
  asset.done(element.to_document_string(content))
}
