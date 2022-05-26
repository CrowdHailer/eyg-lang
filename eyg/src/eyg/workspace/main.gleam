import gleam/io
import gleam/javascript

// gleam javascript make reference
// ui under each application for helpers
// present/display/render or is it more than render because we have to handle things
// Let's do new workspace coding with all the top level things
// and handle the text box or not
// Event is something we can pass to closest
// Active is App or Editor
// Can have a separate tree of things for routing in to the ui
// ["editor", "program", "node"]
// Should this be called app or state?
// Do we want closest and other things to be part of the browser gleam api
// Can choose on the routing layer as well
// an asyn event
// pub fn main() -> Nil {
//     loop(init())
//     // x <- pull()
// }
// external fn new_app() -> Nil = "" "new App"
// // pass in window then use reflect on it
// // show in the chnnel
// // return list of functions returning promises Maybe can keep going. Is there a walk through of different approaches
// // App(body)
// func  () {
//     // a = new_app()
//     // state = new_reference(State)
//     mutate = stateful()
//     window.onclick(fn(event) {
//         mutate(fn(e) => {
//         next = atlier.handle_click(state, event)
//         // set(a.value, {})
//         })
//         settimeout(
//         )
//     })
//     // TODO A transform fn exist to make sure there are no promises or race conditions.
//     // not promises but generator
//     // editor = promises.all()
//     // set(a, editor)
//     fetch("/foo", fn(state) => {state})
//     mutate(fn(e) => e)
//     // continuation
// }
// // Do this in the eyg language to keep pushing over
// fn stateful() {
//     // new reference
//     fn(f) {
// // TODO and set on app
//      }
//  }
pub external type Event

external fn add_event_listener(String, fn(Event) -> a) -> Nil =
  "" "window.addEventListener"

fn stateful() {
  let state = javascript.make_reference(0)

  fn(f) {
    state
    |> javascript.dereference
    |> f
    |> javascript.set_reference(state, _)
    |> io.debug
  }
}

external fn render() -> Nil =
  "../../ffi" "render"

// All the ui functions are going to be just as tricky to deal with
// TODO fetch source
pub fn main() {
  io.debug("starting")
  let modify = stateful()

  add_event_listener(
    "click",
    fn(e) {
      modify(fn(x) {
        io.debug(modify)
        x + 1
      })
    },
  )
  |> io.debug
  render()
  |> io.debug
  //   io.debug(w)
  //   todo("more window")
}
// The goal is to have quicker modification of event and handling so type check all the event and key options are checked
// TODO A link of everything
// Bench is where you run other aps
// loop is one of continuations or click event
// stateful compontents receiving new update values.
// structural type works really well for composing value out of Event<Target<Form<Number>>>
