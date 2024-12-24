import gleam/option.{None, Some}
import lustre/attribute as a
import lustre/element
import lustre/element/html as h
import lustre/event
import supa/auth
import website/components/auth_panel

const secondary_button_classes = "py-2 px-3 text-gray-700 hover:bg-gray-100 rounded-lg font-bold whitespace-nowrap"

fn header_link(target, text) {
  h.a([a.class(secondary_button_classes), a.href(target)], [element.text(text)])
}

fn header_button(event, text) {
  h.button([a.class(secondary_button_classes), event.on_click(event)], [
    element.text(text),
  ])
}

fn action_button(event, text) {
  h.button(
    [
      a.class(
        "inline-block py-2 px-3 rounded-xl text-white font-bold bg-gray-900 border-2 border-gray-900 whitespace-nowrap",
      ),
      event.on_click(event),
    ],
    [element.text(text)],
  )
}

pub fn header(authenticate, session) {
  // z index needed to go over vimeo video embeds
  h.header([a.class("hstack gap-8 p-2 sticky top-0 border-b-2 bg-white z-20")], [
    h.a([a.class("font-bold text-4xl"), a.href("/")], [element.text("EYG")]),
    h.div([a.class("expand hstack gap-2")], [
      header_link("/editor", "Editor"),
      header_link("/documentation", "Documentation"),
    ]),
    case session {
      None ->
        h.div([a.class("flex gap-2")], [
          header_button(authenticate(auth_panel.UserClickedSignIn), "Sign in"),
          action_button(
            authenticate(auth_panel.UserClickedCreateAccount),
            "Get Started",
          ),
        ])
      Some(#(_session, user)) -> {
        let auth.User(email:, ..) = user
        h.div([a.class("flex gap-2"), a.style([#("align-items", "center")])], [
          h.span([], [element.text(email)]),
          action_button(authenticate(auth_panel.UserClickedSignOut), "Sign out"),
        ])
      }
    },
  ])
}

pub fn card(children) {
  h.div(
    [
      a.class(
        "border border-white bg-gray-100 rounded-lg overflow-hidden shadow-xl",
      ),
    ],
    children,
  )
}

pub fn keycap(letter) {
  h.span(
    [
      a.style([
        #("box-shadow", "1px 1px 0px 2px black"),
        #("font-size", "85%"),
        #("font-weight", "bold"),
        #("border-radius", "3px"),
        #("margin", "0 5px"),
        #("width", "19px"),
        #("display", "inline-block"),
        #("text-align", "center"),
      ]),
    ],
    [element.text(letter)],
  )
}

pub fn vimeo_intro() {
  [
    h.div([a.attribute("style", "padding:75% 0 0 0;position:relative;")], [
      h.iframe([
        a.attribute("title", "New Recording - 10/13/2024, 8:14:28 PM"),
        a.attribute(
          "style",
          "position:absolute;top:0;left:0;width:100%;height:100%;",
        ),
        a.attribute(
          "allow",
          "autoplay; fullscreen; picture-in-picture; clipboard-write",
        ),
        a.attribute("frameborder", "0"),
        a.src(
          "https://player.vimeo.com/video/1019199789?h=3ee4fc598d&badge=0&autopause=0&player_id=0&app_id=58479",
        ),
      ]),
    ]),
    h.script([a.src("https://player.vimeo.com/api/player.js")], ""),
  ]
}
