import gleam/list
import gleam/option.{None, Some}
import gleam/string
import lustre
import lustre/attribute as a
import lustre/element
import lustre/element/html as h
import lustre/event
import morph/editable as e
import mysig/asset
import mysig/html
import website/components
import website/components/example
import website/components/example/view
import website/components/snippet
import website/components/tree
import website/routes/common
import website/routes/documentation/state

pub fn app(module, func) {
  use script <- asset.do(asset.bundle(module, func))
  layout([html.empty_lustre(), h.script([a.src(asset.src(script))], "")])
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
  use content <- asset.do(app("website/routes/documentation", "client"))
  asset.done(element.to_document_string(content))
}

pub fn client() {
  let app = lustre.application(state.init, state.update, render)
  let assert Ok(_) = lustre.start(app, "#app", Nil)
  Nil
}

// doc h2
fn title_to_id(text) {
  text
  |> string.lowercase
  |> string.replace(" ", "-")
}

fn h2(text) {
  h.h2([a.class("text-xl mt-8 mb-4 font-bold"), a.id(title_to_id(text))], [
    element.text(text),
  ])
}

fn p(text) {
  h.p([a.class("my-2")], [element.text(text)])
}

fn note(content) {
  h.div(
    [
      a.class("sticky mt-2 top-12 p-2 shadow-md bg-yellow-1"),
      a.style([
        #("align-self", "start"),
        #("flex", "0 0 200px"),
        #("overflow", "hidden"),
      ]),
    ],
    content,
  )
}

fn chapter(_index, title, content, comment) {
  h.div(
    [
      //     a.class("vstack outline-none"),
    //     // make this optional or not have at all
    //   //  a.style([#("min-height", "100vh")])
    ],
    [
      h2(title),
      h.div(
        [
          a.class("md:grid gap-6"),
          a.style([#("grid-template-columns", "1fr 200px")]),
        ],
        [
          h.div([a.class("expand max-w-3xl")], content),
          case comment {
            Some(comment) -> note(comment)
            None ->
              h.div(
                [
                  a.class(""),
                  a.style([#("flex", "0 0 200px"), #("overflow", "hidden")]),
                ],
                [],
              )
          },
        ],
      ),
    ],
  )
}

fn chapter_link(title) {
  h.li([], [
    h.a(
      [
        a.class(
          "border-l-4 border-transparent focus:border-black hover:border-black outline-none inline-block px-2 w-full",
        ),
        a.href("#" <> title_to_id(title)),
      ],
      [element.text(title)],
    ),
  ])
}

fn section_content(title, chapters) {
  element.fragment([
    h.h2([a.class("font-bold text-lg pt-2 px-2")], [element.text(title)]),
    h.ul([], list.map(chapters, chapter_link)),
  ])
}

// simpleter documentation
fn render(state) {
  h.div([a.class("")], [
    components.header(state.AuthMessage, None),
    h.div([a.class("lg:flex px-1 md:px-4 gap-10 mx-auto")], [
      h.div(
        [
          a.class("hidden py-12 top-0 lg:block sticky"),
          a.style([#("align-self", "flex-start")]),
        ],
        [
          h.aside([a.class("w-72 p-6 pb-8 bg-green-100 rounded-2xl")], [
            section_content("Language basics", [
              "Numbers", "Text", "Lists", "Records", "Unions", "Functions",
              "Builtins", "References",
            ]),
            section_content("Advanced features", [
              "Perform Effect", "Handle Effect", "Multiple resumptions",
              "Closure serialization",
            ]),
            section_content("Editor features", ["Copy paste", "Next vacant"]),
            section_content("Advanced", ["Show IR"]),
          ]),
        ],
      ),
      h.div([a.class("py-12")], [
        chapter(
          "1",
          "Introduction",
          [
            p(
              "All examples in this documentation can be run and edited, click on the example code to start editing.",
            ),
            p(
              "EYG uses a structured editor to modify programs
             This editor helps reduce the mistakes you can make, however it can take some getting used to.",
            ),
            p(
              "The side bar explains what keys to use in the editor for each section of the documentation.",
            ),
            ..components.vimeo_intro()
          ],
          Some([
            element.text("moving in editors is done using the arrow keys. Use "),
            components.keycap("d"),
            element.text(" to delete the current selection."),
          ]),
        ),
        chapter(
          "2",
          "Numbers",
          [
            example(state, state.int_key),
            p("Numbers are a positive or negative whole number, of any size."),
            p(
              "Several builtin functions are available for working with number values, they include math operations add, subtract etc and functions for parsing and serializing numerical values.",
            ),
          ],
          Some([
            element.text("press"),
            components.keycap("n"),
            element.text("to insert a number or edit an existing number"),
          ]),
        ),
        chapter(
          "3",
          "Text",
          [
            example(state, state.text_key),
            p(
              "Text segment of any length made up of characters, whitespace and special characters",
            ),
            p(
              "Several builtin functions are available for working with text values such as append, split, uppercase and lowercase.",
            ),
          ],
          Some([
            element.text("press"),
            components.keycap("s"),
            element.text("to insert text or edit existing text"),
          ]),
        ),
        chapter(
          "4",
          "Lists",
          [
            example(state, state.lists_key),
            p(
              "Lists are an ordered collection of value.
          All the values in a list must be of the same type, for example only Numbers or only Text.
          If you need to keep more than one type in the list jump ahead to look at Unions.",
            ),
            p(
              "For working with lists there are builtins to add and remove items from the front of the list, as well as processing all the items in the list",
            ),
            // p("List are implemented as linked lists, this means it is faster to add and remove items from the front of the list.")
          ],
          Some([
            element.text("press"),
            components.keycap("l"),
            element.text("to create a new list and "),
            components.keycap(","),
            element.text(" to add items to a list and"),
            components.keycap("."),
            element.text(" to extend a list."),
          ]),
        ),
        chapter(
          "5",
          "Records",
          [
            example(state, state.records_key),
            p(
              "Records gather related values with each value having a name in the record.
              Different names can store values of different types.",
            ),
            p(
              "When passing records to functions any unused values are ignored.",
            ),
            // Here the greet function accepts any record with a name field,
            // we can pass the alice or bob record to this function, the extra height field on bob will be ignored.",
            example(state, state.overwrite_key),
            p(
              "New records can be created with a subset of their fields overwritten.",
            ),
          ],
          Some([
            element.text("Records can be created or added to by pressing "),
            components.keycap("r"),
            element.text(". To select a field from a record press "),
            components.keycap("g"),
            element.text(". To overwrite fields in a record use "),
            components.keycap("o"),
          ]),
        ),
        chapter(
          "6",
          "Unions",
          [
            example(state, state.unions_key),
            p(
              "Unions are used when a value is one of a selection of possibilities.
            For example when parsing a number from some text, the result might be ok and we have a number or there is no number and so we have a value representing the error.",
            ),
            p(
              "Each possibility in the union is a tagged value, from int_parse values can be tagged Ok or Error.",
            ),
            p(
              "Case statements are used to match on each of the tags that are in the union.",
            ),
            example(state, state.open_case_key),
            p(
              "Case statements can be open and if so, they have a final fallback that is called if none of the previous ones match the tag of the value.",
            ),
          ],
          Some([
            element.text("Create a tagged value by pressing "),
            components.keycap("t"),
            element.text(". Complete case statements are created with "),
            components.keycap("m"),
            element.text(". Open case statements are created with "),
            components.keycap("M"),
            element.text("."),
          ]),
        ),
        chapter(
          "7",
          "Functions",
          [
            example(state, state.functions_key),
            p(
              "Functions allow you to create reusable behaviour in your application.",
            ),
            p(
              "All functions, including builtins, can be called with only some of the arguments and will return a function that accepts the remaining arguments.",
            ),
            p("All functions can be passed to other functions"),
            example(state, state.fix_key),
            p(
              "fix is a fixpoint operator, use it to write recursive functions.",
            ),
          ],
          Some([
            element.text("press"),
            components.keycap("f"),
            element.text("to insert text or edit existing text"),
          ]),
        ),
        chapter(
          "8",
          "Builtins",
          [
            example(state, state.builtins_key),
            p(
              "Builtins are the base functions that your program is built up from.",
            ),
            p(
              "There are builtins to work with all the different values in the EYG language.
              We have seen several of them so far are we introduced each type of value, i.e. int_add and string_append.",
            ),
            p(
              "Builtins are called like any other function.
            Also like functions they can be passed only some of their arguments and will return a function that can be called later with the remaing arguments.",
            ),
          ],
          Some([
            element.text("press"),
            components.keycap("j"),
            element.text("to insert one of the available builtins."),
          ]),
        ),
        chapter(
          "9",
          "Named references",
          [
            example(state, state.references_key),
            p(
              "Rely on packages directly in your program with immutable references. No need for any package manifest or lockfile.",
            ),
            p(
              "The std package has functionality for lists, numbers and strings with more being added.",
            ),
            p(
              "Name registration is currently a concierge driven process, i.e. you will need to contact us directly for one.
            This process will be opened up once we have commited to a 1.0 format for the EYG storage format.",
            ),
            //   p(
          //     "Every fragment of EYG program has a unique reference.
          // Once you have a reference to a program that reference is guaranteed to always point to the same fragment.",
          //   ),
          //   p(
          //     "These fragments are how larger programs in EYG. A reference can be at any point in a place of a value.",
          //   ),
          //   p(
          //     "The three refererences in this example are available in the web playgrounds.",
          //   ),
          //   p(
          //     "Work is underway to add more support for finding and authoring references.",
          //   ),
          ],
          Some([
            element.text("press"),
            components.keycap("#"),
            element.text("to insert a reference."),
          ]),
        ),
        chapter(
          "8",
          "Perform effect",
          [
            example(state, state.perform_key),
            p(
              "A useful program must eventally interact with the world outside the computer.
            Running the example above will prompt the user for there name.
            A program uses perform to create an effect.",
            ),
            p(
              "The Prompt effect sends information to the outside world, i.e. the text \"what is your name message\".
              It also receives data from the outside world, i.e. the response to the question or and Error if no response is given.",
              //   "Just as imporant is a responding to effects.
            // Programs without effects (called pure) will always return the same answer.
            // This next example introduces some non-determinism with the Choose effect.",
            ),
            p(
              "Some effects only send out information, such as a Log effect, in which case the return value will be an empty record.
            Some effects only pull information from the outside world, such as a Random effect, such effects are called with an empty record",
            ),
          ],
          Some([
            element.text("press"),
            components.keycap("p"),
            element.text("to insert perform to trigger an effect"),
          ]),
        ),
        chapter(
          "9",
          "Handle effect",
          [
            example(state, state.handle_key),
            p(
              "Handlers are a mechanism to intercept effects performed within a function.
              In this example, running the code will show that the inner function performs two alerts, without us having to dismiss the two alerts manually.",
            ),
            p(
              "When testing functions it is useful to control the effects they perform.",
            ),
          ],
          Some([
            element.text("press"),
            components.keycap("h"),
            element.text("to insert to handle an effect"),
          ]),
        ),
        chapter(
          "10",
          "Multiple resumptions",
          [
            example(state, state.multiple_resume_key),
            p(
              "Handlers give the ability to resume code multiple times.
              In this example the function resumes the remaining code with both True and False values.
              The final output is the set of all possible output that the exec function could produce.",
            ),
          ],
          None,
        ),
        // Abort and flow control
        // chapter("External", [example(state, state.Externals)], None),
        // chapter(
        //   "11",
        //   "Closure serialization",
        //   [
        //     example(state, state.capture_key),
        //     p(
        //       "In EYG any value can be captured, and transformed to EYG source code.
        //       This includes functions and their environments and effect handlers applicable at that time.",
        //     ),
        //     p(
        //       "Note, only the required environment is captured. In this example the variable ignore is not part of the bundle.",
        //     ),
        //     p(
        //       "Closure capture and serialization allows EYG programs to extend over multiple machines.
        //       Source code can be sent to another interpreter or transpiled.",
        //     ),
        //   ],
        //   None,
        // ),
        chapter(
          "12",
          "Copy paste",
          [
            p(
              "Any expression can be copied to the clip board or pasted from it. Press 'y' to copy and 'Y' to paste",
            ),
            p("To increase the code selection press 'a'"),
            p(
              "Most EYG development is done by copy and pasting code from the editor to your own library of snippets.
            These snippets can be stored in Notion, Google Drive or on your local file system.",
            ),
          ],
          None,
        ),
        chapter(
          "12",
          "Next vacant",
          [
            p(
              "A vacant expression is one that has not been written yet. You will see them labelled as 'Vacant' in the editor.",
            ),
            p(
              "Press 'Space' and jump to the next missing part of your program.",
            ),
          ],
          None,
        ),
        chapter(
          "13",
          "Show IR",
          [
            p("The intermediate representation (IR) is a stable interface."),
            p("Press '?' in any example to toggle showing the IR"),
          ],
          None,
        ),
        h.div([a.style([#("height", "30vh")])], []),
        components.footer(),
      ]),
    ]),
  ])
}

fn example(state: state.State, identifier) {
  let example = state.get_example(state, identifier)
  element.fragment([
    example
      |> view.render
      |> element.map(state.ExampleMessage(identifier, _)),
    case state.show_help {
      True ->
        h.pre(
          [a.class("leading-none p-2 bg-gray-200")],
          tree.lines(example.snippet.editable |> e.to_annotated([]))
            |> list.map(fn(line) { element.text(line <> "\n") }),
        )
      False -> element.none()
    },
  ])
}
