import eyg/sync/supabase
import gleam/io
import gleam/javascript/promise
import gleam/option.{None, Some}
import lustre/attribute as a
import lustre/effect
import lustre/element
import lustre/element/html as h
import lustre/event
import midas/browser
import midas/task as t

pub type State {
  State(active: Bool, status: Status, email_address: String)
}

pub type Status {
  EnterEmail
  AwaitCode
}

pub fn init(_) {
  State(False, EnterEmail, "")
}

pub type Message {
  UserClickedAuthenticate
  UserClickedSendCode
  TaskToSendCodeCompleted
}

pub type Event {
  SendCode(email_address: String)
}

pub fn send_code(email_address) {
  use response <- t.do(supabase.sign_in_with_otp(email_address))
  t.done(TaskToSendCodeCompleted)
}

pub fn dispatch(cmd, wrapper) {
  case cmd {
    Some(SendCode(email_address)) ->
      effect.from(fn(d) {
        promise.map(browser.run(send_code(email_address)), fn(result) {
          let response = case result {
            Ok(result) -> TaskToSendCodeCompleted
            Error(reason) -> todo as "task failed"
          }
          d(wrapper(response))
        })
        Nil
      })
    None -> effect.none()
  }
}

pub fn update(state, message) {
  case message {
    UserClickedAuthenticate -> #(State(True, EnterEmail, ""), None)
    UserClickedSendCode -> #(
      State(..state, status: AwaitCode),
      Some(SendCode(state.email_address)),
    )
    TaskToSendCodeCompleted -> {
      io.debug("sent")
      #(state, None)
    }
  }
}

fn modal(content) {
  h.div([a.class("fixed inset-0 bg-gray-100 bg-opacity-40 vstack z-10")], [
    h.div([a.class("w-full vstack")], [
      h.div(
        [a.class("w-full max-w-sm bg-white neo-shadow border-2 border-black")],
        content,
      ),
    ]),
  ])
}

pub fn render() {
  modal([
    h.div([a.class("p-6")], [
      h.div([a.class("hstack")], [
        h.img([a.class("w-8"), a.src("https://eyg.run/assets/pea.webp")]),
        h.span([a.class("expand text-lg text-gray-800")], [element.text("EYG")]),
      ]),
      h.div([a.class("mt-6")], [
        h.h2([a.class("text-xl font-bold underline")], [element.text("Log in")]),
        h.p([], [element.text("We'll send a code to log in")]),
      ]),
      h.form([a.class("mt-6"), event.on_submit(UserClickedSendCode)], [
        h.div([], [
          h.input([
            a.type_("email"),
            a.required(True),
            a.class("w-full p-1 bg-gray-100"),
            a.placeholder("email address"),
          ]),
        ]),
        h.button(
          [
            a.class(
              "w-full mt-2 py-2 px-3  text-white font-bold bg-gray-900 border-2 border-gray-900",
            ),
          ],
          [element.text("Send code")],
        ),
      ]),
    ]),
  ])
}
