import gleam/list
import gleam/listx
import gleam/string
import lustre/attribute as a
import lustre/element.{text}
import lustre/element/html as h
import lustre/event
import morph/utils

// All editing of labels is handled by a picker,
// in some cases there are no suggestions
// in some cases any label in the program can be suggested
pub type Picker {
  Typing(value: String, suggestions: List(#(String, String)))
  Scrolling(
    filtered: listx.Cleave(#(String, String)),
    suggestions: List(#(String, String)),
  )
}

pub fn new(value, suggestions) {
  Typing(value, suggestions)
}

pub type Message {
  Updated(picker: Picker)
  Decided(value: String)
  Dismissed
}

pub fn render(picker) {
  let #(filter, suggestions, index) = case picker {
    Typing(value, suggestions) -> {
      let filtered =
        list.filter(suggestions, fn(suggestion) {
          let #(name, _item) = suggestion
          string.contains(name, value)
        })
      // TODO make size configurable, show all if never scrolling i.e. never clicked
      // |> list.take(11)
      #(value, filtered, -1)
    }
    // I think better scrolling would need to take into account up or down direction
    Scrolling(cleave, _suggestions) -> {
      let index = list.length(cleave.0)
      let pre = list.take(cleave.0, 5)
      let filtered =
        listx.gather_around(
          pre,
          cleave.1,
          list.take(cleave.2, 10 - list.length(pre)),
        )
      #(cleave.1.0, filtered, index - list.length(list.drop(cleave.0, 5)))
    }
  }
  do_render(picker, filter, suggestions, index)
}

fn do_render(picker, filter, suggestions, index) {
  h.form(
    [
      a.style([
        #(
          "font-family",
          "ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, \"Liberation Mono\", \"Courier New\", monospace",
        ),
      ]),
      event.on_submit(on_submit(picker)),
    ],
    [
      h.input([
        a.style([
          #("line-height", "inherit"),
          #("color", "inherit"),
          #("font-family", "inherit"),
          #("font-size", "100%"),
          #("margin", "0"),
          #("outline", "2px solid transparent"),
          #("outline-offset", "2px"),
          #("padding", ".25rem"),
          #("background-color", "transparent"),
          #("border-style", "solid"),
          #("border-color", "rgb(55, 65, 81)"),
          #("border-width", "0"),
          #("border-left-width", "8px"),
          #("width", "100%"),
          #("display", "block"),
        ]),
        a.id("focus-input"),
        a.value(filter),
        a.attribute("autocomplete", "off"),
        a.attribute("autofocus", "true"),
        a.required(True),
        utils.on_hotkey(on_keydown(_, picker)),
        event.on_input(on_input(_, picker)),
      ]),
      h.hr([
        a.style([
          #("border-color", "rgb(55, 65, 81)"),
          #("margin-top", ".25rem"),
          #("margin-bottom", ".25rem"),
          #("margin-left", "10rem"),
          #("margin-right", "10rem"),
          #("border-top-width", "1px"),
        ]),
      ]),
      // event.on_click(Do(apply)),
      ..list.index_map(suggestions, fn(line, i) {
        let #(name, detail) = line
        h.div(
          [
            a.style([
              #("padding-top", ".25rem"),
              #("padding-bottom", ".25rem"),
              #("padding-left", ".75rem"),
              #("padding-right", ".75rem"),
              #("display", "flex"),
              ..case i == index {
                False -> []
                True -> [
                  #("background-color", "rgb(31, 41, 55)"),
                  #("color", "rgb(255, 255, 255)"),
                ]
              }
            ]),
            event.on_click(Decided(name)),
          ],
          [
            h.span([a.style([#("font-weight", "700")])], [text(name)]),
            h.span([a.style([#("flex-grow", "1")])], [text(": ")]),
            h.span(
              [
                a.style([
                  #("padding-left", ".5rem"),
                  #("overflow", "hidden"),
                  #("text-overflow", "ellipsis"),
                  #("white-space", "nowrap"),
                ]),
              ],
              [text(detail)],
            ),
          ],
        )
      })
    ],
  )
}

fn on_submit(picker) {
  Decided(current(picker))
}

pub fn current(picker) {
  case picker {
    Typing(value, _) -> value
    Scrolling(#(_, #(value, _), _), _) -> value
  }
}

fn on_keydown(key, picker) {
  case picker, key {
    _, "Escape" -> Dismissed

    Typing(value, suggestions), " " -> {
      let picker = case filter_suggestions(suggestions, value) {
        [] -> Typing(value, suggestions)
        [next, ..post] -> Scrolling(#([], next, post), suggestions)
      }
      Updated(picker)
    }
    Typing(value, suggestions), "ArrowDown" -> {
      let picker = case filter_suggestions(suggestions, value) {
        [] -> Typing(value, suggestions)
        [next, ..post] -> Scrolling(#([], next, post), suggestions)
      }
      Updated(picker)
    }

    Scrolling(#(pre, current, [next, ..post]), suggestions), "ArrowDown" -> {
      let picker = Scrolling(#([current, ..pre], next, post), suggestions)
      Updated(picker)
    }
    Scrolling(#([next, ..pre], current, post), suggestions), "ArrowUp" -> {
      let picker = Scrolling(#(pre, next, [current, ..post]), suggestions)
      Updated(picker)
    }
    _, _ -> Updated(picker)
  }
}

fn filter_suggestions(suggestions, filter) {
  list.filter(suggestions, fn(suggestion) {
    let #(name, _item) = suggestion
    string.contains(name, filter)
  })
}

fn on_input(new, picker) {
  let picker = case picker {
    Typing(_old, suggestions) -> Typing(new, suggestions)
    Scrolling(_cleave, suggestions) -> Typing(new, suggestions)
  }
  Updated(picker)
}
