import eyg/sync/supabase
import gleam/javascript/promise
import gleam/option.{type Option, None, Some}
import lustre/attribute as a
import lustre/effect
import lustre/element
import lustre/element/html as h
import lustre/event
import midas/browser
import snag.{type Snag}

pub type State {
  State(
    active: Bool,
    status: Status,
    email_address: String,
    code: String,
    error: Option(Snag),
    session: Option(#(supabase.Session, supabase.User)),
  )
}

pub type Status {
  CreateAccount
  SignIn
  AwaitCode
}

pub fn init(_) {
  #(State(False, SignIn, "", "", None, None), Some(LoadSession))
}

pub type Message {
  TaskToLoadSessionCompleted(
    Result(Option(#(supabase.Session, supabase.User)), Snag),
  )
  UserClickedCreateAccount
  UserClickedSignIn
  UserInputedEmailAddress(String)
  UserClickedSendCode
  TaskToSendCodeCompleted(Result(Nil, Snag))
  UserInputedCode(String)
  UserClickedVerifyCode
  TaskToVerifyCodeCompleted(Result(#(supabase.Session, supabase.User), Snag))
  TaskToSaveSessionCompleted(Result(Nil, Snag))
  UserClickedSignOut
  TaskToDeleteSessionCompleted(Result(Nil, Snag))
  Cancel
}

pub type Task {
  LoadSession
  SendCode(email_address: String)
  VerifyCode(email_address: String, code: String)
  SaveSession(supabase.Session, supabase.User)
  DeleteSession
}

pub fn dispatch(cmd, wrapper) {
  case cmd {
    Some(cmd) -> {
      let work = case cmd {
        LoadSession -> promise.resolve(TaskToLoadSessionCompleted(Ok(None)))
        SendCode(email_address) ->
          promise.map(
            browser.run(supabase.sign_in_with_otp(email_address)),
            fn(result) { TaskToSendCodeCompleted(result) },
          )
        VerifyCode(email_address, code) ->
          promise.map(
            browser.run(supabase.verify_otp(email_address, code)),
            fn(result) { TaskToVerifyCodeCompleted(result) },
          )
        SaveSession(_, _) ->
          promise.resolve(TaskToSaveSessionCompleted(Ok(Nil)))
        DeleteSession -> promise.resolve(TaskToDeleteSessionCompleted(Ok(Nil)))
      }
      effect.from(fn(d) {
        promise.map(work, fn(msg) { d(wrapper(msg)) })
        Nil
      })
    }
    None -> effect.none()
  }
}

pub fn update(state, message) {
  case message {
    TaskToLoadSessionCompleted(result) -> #(
      case result {
        Ok(session) -> State(..state, session: session)
        Error(_) -> state
      },
      None,
    )
    UserClickedCreateAccount -> #(
      State(..state, active: True, status: CreateAccount),
      None,
    )
    UserClickedSignIn -> #(State(..state, active: True, status: SignIn), None)

    UserInputedEmailAddress(new) -> #(State(..state, email_address: new), None)
    UserClickedSendCode -> #(
      State(..state, status: AwaitCode),
      Some(SendCode(state.email_address)),
    )
    TaskToSendCodeCompleted(re) ->
      case re {
        Ok(Nil) -> #(state, None)
        Error(reason) -> #(State(..state, error: Some(reason)), None)
      }
    UserInputedCode(new) -> #(State(..state, code: new), None)
    UserClickedVerifyCode -> #(
      State(..state, status: AwaitCode),
      Some(VerifyCode(state.email_address, state.code)),
    )
    TaskToVerifyCodeCompleted(result) ->
      case result {
        Ok(#(session, user)) -> {
          let state = State(..state, session: Some(#(session, user)))
          #(state, Some(SaveSession(session, user)))
        }
        Error(reason) -> #(State(..state, error: Some(reason)), None)
      }
    TaskToSaveSessionCompleted(result) ->
      case result {
        Ok(Nil) -> #(State(..state, active: False), None)
        Error(reason) -> #(State(..state, error: Some(reason)), None)
      }
    UserClickedSignOut -> #(state, Some(DeleteSession))
    TaskToDeleteSessionCompleted(result) ->
      case result {
        Ok(Nil) -> #(
          State(..state, session: None, email_address: "", code: ""),
          None,
        )
        Error(reason) -> #(State(..state, error: Some(reason)), None)
      }

    Cancel -> #(State(..state, active: False), None)
  }
}

fn modal(content) {
  element.fragment([
    h.div(
      [
        a.class("fixed inset-0 bg-gray-100 bg-opacity-40 vstack z-10"),
        event.on_click(Cancel),
      ],
      [],
    ),
    h.div(
      [
        a.class(
          "-translate-x-1/2 -translate-y-1/2 fixed left-1/2 max-w-md top-1/2 transform translate-x-1/2 w-full z-20",
        ),
      ],
      [
        h.div(
          [a.class("w-full max-w-md bg-white neo-shadow border-2 border-black")],
          content,
        ),
      ],
    ),
  ])
}

fn card_content(title, paragraph, error) {
  element.fragment([
    h.div([a.class("mt-6")], [
      h.h2([a.class("text-xl font-bold")], [element.text(title)]),
      h.p([a.class("mt-2")], paragraph),
    ]),
    case error {
      None -> element.none()
      Some(reason) ->
        h.div([a.class("mt-6 p-2 bg-red-200")], [
          element.text(snag.pretty_print(reason)),
        ])
    },
  ])
}

fn email_form(email_address) {
  h.form([a.class("mt-6"), event.on_submit(UserClickedSendCode)], [
    h.div([], [
      h.input([
        a.type_("email"),
        a.required(True),
        a.class("w-full p-1 bg-gray-100"),
        a.placeholder("email address"),
        event.on_input(UserInputedEmailAddress),
        a.value(email_address),
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
  ])
}

fn inline_button(event, text) {
  h.button([a.class("underline text-green-600"), event.on_click(event)], [
    element.text(text),
  ])
}

fn mild(elements) {
  h.span([a.class("text-gray-600")], elements)
}

pub fn render(state) {
  let State(email_address: email_address, ..) = state
  modal([
    h.div([a.class("p-6")], [
      h.div([a.class("hstack")], [
        h.img([a.class("w-8"), a.src("https://eyg.run/assets/pea.webp")]),
        h.span([a.class("expand text-lg text-gray-800")], [element.text("EYG")]),
      ]),
      ..case state.status {
        CreateAccount -> [
          card_content(
            "Create new account",
            [
              mild([element.text("Have an account? ")]),
              inline_button(UserClickedSignIn, "Login."),
            ],
            state.error,
          ),
          email_form(email_address),
        ]
        SignIn -> [
          card_content(
            "Sign in",
            [
              mild([element.text("Don't have an account? ")]),
              inline_button(UserClickedCreateAccount, "Create account."),
            ],
            state.error,
          ),
          email_form(email_address),
        ]
        AwaitCode -> [
          card_content(
            "Verify code",
            [
              mild([
                element.text("Enter the "),
                h.strong([a.class("font-bold")], [element.text("6 ")]),
                element.text("digit code we sent to:"),
                h.br([]),
              ]),
              h.span([a.class("font-bold")], [element.text(state.email_address)]),
            ],
            state.error,
          ),
          h.form([a.class("mt-6"), event.on_submit(UserClickedVerifyCode)], [
            h.div([], [
              h.input([
                a.required(True),
                a.class("w-full p-1 bg-gray-100"),
                a.placeholder("code"),
                event.on_input(UserInputedCode),
                a.value(state.code),
              ]),
            ]),
            h.button(
              [
                a.class(
                  "w-full mt-2 py-2 px-3  text-white font-bold bg-gray-900 border-2 border-gray-900",
                ),
              ],
              [element.text("Verify")],
            ),
          ]),
        ]
      }
    ]),
  ])
}
