import gleam/io
import gleam/javascript/array
import plinth/browser/document
import easel/embed

// TODO this is what boots up all the scripts eventually based on hashes. for now we key switch on strings

pub fn run() {
  let containers = document.query_selector_all("[data-run]")
  // could register click handler here for load up. in which case eyg .ready is a thing
  // or on eyg.clock
  // 
  // document.add_event_listener(document.document(), "click", fn(lookup closet click handler))
  // TODO how do i handle adding state to something being active i.e. in memory value of state
  // Do I have a render context
  // For now lets just load and hydrate, a single button with on click listener is probably not going to work too hard.
  array.map(containers, start)
}

fn start(container) {
  let assert Ok(program) = document.dataset_get(container, "run")
  case program {
    "editor" -> embed.fullscreen(container)
    _ -> {
      io.debug(#("unknown program", program))
      Nil
    }
  }
}
