import gleam/list
import gleam/listx
import gleam/string
import lustre/attribute as a
import lustre/element.{text}
import lustre/element/html as h
import lustre/event

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

pub fn render(picker, dispatch) {
  let #(filter, suggestions, index) = case picker {
    Typing(value, suggestions) -> {
      let filtered =
        list.filter(suggestions, fn(suggestion) {
          let #(name, _item) = suggestion
          string.contains(name, value)
        })
        |> list.take(11)
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
      #({ cleave.1 }.0, filtered, index - list.length(list.drop(cleave.0, 5)))
    }
  }
  h.form([event.on_submit(on_submit(picker, dispatch))], [
    // h.div([a.class("w-full p-2")], []),
    h.input([
      a.class(
        "block w-full bg-transparent border-l-8 border-gray-700 focus:border-gray-300 p-1 outline-none",
      ),
      a.id("focus-input"),
      a.value(filter),
      a.attribute("autocomplete", "off"),
      a.attribute("autofocus", "true"),
      event.on_keydown(on_keydown(_, picker, dispatch)),
      event.on_input(on_input(_, picker, dispatch)),
    ]),
    h.hr([a.class("mx-40 my-1 border-gray-700")]),
    // event.on_click(Do(apply)),
    ..list.index_map(suggestions, fn(line, i) {
      let #(name, detail) = line
      h.div(
        [
          a.class("px-3 py-1 flex"),
          a.classes([#("bg-gray-800 text-white", i == index)]),
        ],
        [
          h.span([a.class("font-bold")], [text(name)]),
          h.span([a.class("flex-grow")], [text(": ")]),
          h.span([a.class("pl-2 whitespace-nowrap truncate")], [text(detail)]),
        ],
      )
    })
  ])
}

fn on_submit(picker, dispatch) {
  let value = case picker {
    Typing(value, _) -> value
    Scrolling(#(_, #(value, _), _), _) -> value
  }
  dispatch(Decided(value))
}

fn on_keydown(key, picker, dispatch) {
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
  |> dispatch
}

fn filter_suggestions(suggestions, filter) {
  list.filter(suggestions, fn(suggestion) {
    let #(name, _item) = suggestion
    string.contains(name, filter)
  })
}

fn on_input(new, picker, dispatch) {
  let picker = case picker {
    Typing(_old, suggestions) -> Typing(new, suggestions)
    Scrolling(_cleave, suggestions) -> Typing(new, suggestions)
  }
  Updated(picker)
  |> dispatch
}
