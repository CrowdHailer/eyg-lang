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

fn chapter(title, content, comment) {
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
  ])
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
          "Numbers",
          [
            example(state, state.Numbers),
            p("Numbers represent all positive or negative whole numbers."),
            p(
              "Builtins function are available for working with number values, they include math operations add, subtract etc and functions for parsing and serializing numerical values.",
            ),
          ],
          Some([
            element.text("press"),
            components.keycap("n"),
            element.text("to insert a number or edit an existing number"),
          ]),
        ),
        chapter(
          "Text",
          [example(state, state.Text), p("passages of words and whitespace")],
          Some([
            element.text("press"),
            components.keycap("s"),
            element.text("to insert text or edit existing text"),
          ]),
        ),
        chapter(
          "Functions",
          [example(state, state.Functions), p("resuable behaviour")],
          Some([
            element.text("press"),
            components.keycap("f"),
            element.text("to insert text or edit existing text"),
          ]),
        ),
        chapter(
          "Lists",
          [
            example(state, state.Lists),
            p(
              "List are an ordered collection of value.
          All the values in a list must be of the same type, for example only Numbers or only Text.
          If you need to keep more than one type in the list jump ahead to look at Unions.",
            ),
          ],
          Some([
            element.text("press"),
            components.keycap("f"),
            element.text("to insert text or edit existing text"),
          ]),
        ),
        chapter(
          "Records",
          [
            example(state, state.Records),
            p(
              "Records are used to gather related values.
              Each value in the record has a name.
              Different names can store values of different types.",
            ),
            p(
              "When passing records to functions any unused values are ignored.
            Here the greet function accepts any record with a name field,
            we can pass the alice or bob record to this function, the extra height field on bob will be ignored.",
            ),
          ],
          Some([
            element.text("Record can be created or added to by pressing "),
            components.keycap("r"),
            element.text(". To select a field from a record press "),
            components.keycap("g"),
          ]),
        ),
        chapter(
          "Unions",
          [
            example(state, state.Unions),
            p(
              "Unions are used when a value is on of a selection of possibilities.
            For example when parsing a number from some text, the result might be ok and we have a number or there is no number and so we have a value representing the error.",
            ),
          ],
          Some([
            element.text("Create a union by pressing "),
            components.keycap("t"),
            element.text("."),
          ]),
        ),
        chapter("External", [example(state, state.Externals)], None),
        // overwriting fields in a record
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
