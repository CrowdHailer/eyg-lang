import eyg/website/components
import eyg/website/components/snippet
import eyg/website/documentation/state
import eyg/website/page
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import lustre
import lustre/attribute as a
import lustre/element
import lustre/element/html as h

pub fn client() {
  let app = lustre.application(state.init, state.update, render)
  let assert Ok(_) = lustre.start(app, "#app", Nil)
  Nil
}

fn h1(text) {
  h.h1([a.class("text-2xl underline font-bold mt-8 mb-4")], [element.text(text)])
}

// doc h2
fn title_to_id(text) {
  text
  |> string.lowercase
  |> string.replace(" ", "-")
}

fn h2(text) {
  h.h2([a.class("text-xl my-4 font-bold"), a.id(title_to_id(text))], [
    element.text(text),
  ])
}

fn p(text) {
  h.p([a.class("my-2")], [element.text(text)])
}

fn note(content) {
  h.div(
    [
      a.class("sticky mt-8 top-4 p-2 shadow-md bg-white bg-opacity-40"),
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
      a.class("vstack outline-none"),
      // make this optional or not have at all
    //  a.style([#("min-height", "100vh")])
    ],
    [
      h.div([a.class("hstack gap-6")], [
        h.div([a.class("expand")], [h2(title), ..content]),
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
      ]),
    ],
  )
}

fn chapter_link(title) {
  h.li([], [
    h.a(
      [
        a.class(
          "border-l-4 border-r-4 border-white focus:border-black hover:border-black outline-none inline-block px-2 w-full",
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
  h.div([a.class("yellow-gradient")], [
    components.header(),
    h.div([a.class("hstack px-4 gap-10 mx-auto")], [
      h.div([a.class("cover")], [
        h.aside([a.class("w-72 bg-white neo-shadow")], [
          section_content("Language basics", [
            "Numbers", "Text", "Functions", "Lists", "Records", "Unions",
          ]),
          section_content("Type checking", [
            "Incorrect types", "Extensible Records",
          ]),
          section_content("Editor features", ["Copy paste", "Saving"]),
          section_content("Effects", ["Perform", "Handle", "External"]),
        ]),
      ]),
      h.div([a.class("expand max-w-4xl")], [
        h1("EYG documentation"),
        chapter(
          "1",
          "Introduction",
          [
            p(
              "All examples in this documentation can be run and edited, click on the example code to start editing.",
            ),
            p(
              "EYG uses a structured editor to modify programs
             This editor helps reduce the mistakes you can make, however it can take some getting used to.
             The side bar explains what key to press in the editor",
            ),
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
            components.keycap("y"),
            element.text(" to add items to a list."),
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
          "Perfoming effects",
          [
            example(state, state.prompt_key),
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
          "Handling effects",
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
        chapter("11", "Capture", [example(state, state.capture_key)], None),
      ]),
    ]),
  ])
}

fn example(state: state.State, identifier) {
  let snippet = state.get_example(state, identifier)
  snippet.render(snippet)
  |> element.map(state.SnippetMessage(identifier, _))
}

pub fn page(bundle) {
  page.app("eyg/website/documentation", "client", bundle)
}
