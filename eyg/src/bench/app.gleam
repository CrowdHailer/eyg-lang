import gleam/dynamic
import gleam/io
import gleam/option.{type Option, None, Some}
import gleam/javascript/promise
import plinth/browser/media_capture
import lustre
import lustre/attribute as a
import lustre/element.{text}
import lustre/element/html.{button, div, input}
import lustre/event.{on_click}
import lustre/effect

// run depends on page and page depends on state so need separate file for state/model
pub fn run() {
  let app = lustre.application(init, update, render)
  let assert Ok(_) = lustre.start(app, "#app", Nil)
  Nil
}

fn init(_) {
  #(None, effect.none())
}

fn update(state, action) {
  let Wrap(action) = action
  action(state)
}

pub type State =
  Option(media_capture.MediaStream)

pub type Wrap {
  Wrap(fn(State) -> #(State, effect.Effect(Wrap)))
}

fn render(state) {
  div([], [
    button([on_click(Wrap(start_video))], [text("start_video")]),
    // this only works on mobile, otherwise you get a file and you don't really know what the user will see
    // I have a webcam on desktop
    input([
      a.type_("file"),
      a.attribute("capture", "user"),
      a.accept(["video/*"]),
    ]),
    html.br([]),
    html.p([], [text("output")]),
    case state {
      None -> text("later")
      Some(stream) ->
        html.video(
          [
            a.style([#("background", "red")]),
            // a.attribute(
            //   "srcObject",
            //   dynamic.unsafe_coerce(dynamic.from(stream)),
            // ),
            a.autoplay(True),
            a.property("srcObject", stream),
          ],
          [],
        )
    },
  ])
}

fn start_video(_) {
  io.debug("starting")

  #(
    None,
    effect.from(fn(d) {
      promise.map(media_capture.get_user_media(), fn(stream) {
        case stream {
          Error(reason) -> io.debug(reason)
          Ok(stream) -> {
            io.debug(stream)
            d(Wrap(fn(_) { #(Some(stream), effect.none()) }))
            ""
          }
        }
        Nil
      })
      Nil
    }),
  )
}
