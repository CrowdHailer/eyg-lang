import gleam/list
import gleam/option.{None, Some}
import gleroglero/outline
import lustre/attribute as a
import lustre/element/html as h
import lustre/event
import website/routes/sign/state.{State}

pub fn model(state) {
  case state {
    // Look at the keys
    State(mode: state.ViewKeys, database: state.Fetching, ..) ->
      SelectKeyAndProfile(state.Fetching)
    State(mode: state.ViewKeys, database: state.Fetched(_), ..) ->
      SelectKeyAndProfile(state.Fetched(state.keypairs))
    // State(keypairs: state.Fetching(..), ..) -> Loading
    // State(keypairs: state.Failed(..), ..) -> todo
    State(mode: state.SetupKey, ..) -> Setup
    State(mode: state.CreatingAccount, ..) -> CreateNewAccount
    State(keypairs:, ..) -> todo as "SelectKeyAndProfile(keypairs)"
  }
}

pub type Model {
  // Failed(message: String)
  // This is the overview mode, if no keys then highlight the setup button
  SelectKeyAndProfile(keys: state.Fetching(List(state.Key)))
  // Choose to setup a key in a new or existing account
  Setup
  CreateNewAccount
  // Loading
  Confirm
  Link
}

pub fn render(model) {
  case model {
    // Failed(message:) -> layout([h.text("failed " <> message)], [])
    // Loading -> layout([h.text("loading")], [])
    Setup ->
      layout(
        [
          full_row_button(
            state.UserClickedCreateNewAccount,
            outline.user_plus(),
            "Create new account",
          ),
          full_row_button(
            state.UserClickedAddDeviceToAccount,
            outline.qr_code(),
            "Sign in to account",
          ),
        ],
        [
          full_row_button(
            state.UserClickedSignPayload,
            outline.backspace(),
            "Back",
          ),
        ],
      )
    CreateNewAccount ->
      layout(
        [
          h.form(
            [
              event.on_submit(fn(input) {
                let assert [#("name", name)] = input
                echo input
                state.UserConfirmAccountCreation(name)
              }),
            ],
            [
              h.input([a.class("mx-2 p-2 rounded-lg w-full"), a.name("name")]),
              h.div([a.styles([#("text-align", "right")]), a.class("cover")], [
                h.button(
                  [
                    a.class("p-2 rounded"),
                    a.styles([
                      #(
                        "background",
                        "linear-gradient(135deg, #a7f3d0 0%, #6ee7b7 25%, #34d399 50%, #10b981 75%, #059669 100%)",
                      ),
                    ]),
                  ],
                  [h.text("confirm")],
                ),
              ]),
            ],
          ),
        ],
        [
          full_row_button(
            state.UserClickedSignPayload,
            outline.backspace(),
            "Back",
          ),
        ],
      )
    Confirm ->
      layout(
        [
          h.div([a.class("cover bg-white p-2")], [
            h.dl([], [
              h.dt([a.class("font-bold italic")], [h.text("type")]),
              h.dd([a.class("ml-8 mb-2")], [h.text("publish release")]),
              h.dt([a.class("font-bold italic")], [h.text("package")]),
              h.dd([a.class("ml-8 mb-2")], [h.text("standard")]),
              h.dt([a.class("font-bold italic")], [h.text("version")]),
              h.dd([a.class("ml-8 mb-2")], [h.text("2")]),
              h.dt([a.class("font-bold italic")], [h.text("module")]),
              h.dd([a.class("ml-8 mb-2")], [
                h.text("cadcdac23rgw45ur67ndfgdgw4"),
              ]),
            ]),
          ]),
          full_row_button(
            state.UserClickedSignPayload,
            outline.cloud_arrow_up(),
            "Sign",
          ),
        ],
        [],
      )
    SelectKeyAndProfile(keypairs) ->
      layout(
        case keypairs {
          state.Fetching -> [
            full_row_button_subtext(
              outline.key(),
              h.div([a.class("shimmer skeleton-line")], []),
              h.div([a.class("shimmer skeleton-line short")], []),
              None,
            ),
            full_row_button_subtext(
              outline.key(),
              h.div([a.class("shimmer skeleton-line")], []),
              h.div([a.class("shimmer skeleton-line short")], []),
              None,
            ),
          ]
          state.Fetched([]) -> [
            h.div([], [h.text("click below to setup your first key")]),
          ]
          state.Fetched(keypairs) ->
            list.map(keypairs, fn(keypair) {
              full_row_button_subtext(
                outline.key(),
                h.text(keypair.entity_nickname),
                h.text(keypair.id),
                Some(state.UserClickedViewAccount),
              )
            })
          // [
          //   // full_row_button_subtext(
          // //   outline.key(),
          // //   "EYG account",
          // //   "ab:1s:dx:3s:27",
          // // ),
          // // full_row_button_subtext(
          // //   outline.key(),
          // //   "Peter @ work",
          // //   "ab:1s:dx:3s:27",
          // // ),
          // ]
          state.Failed(..) -> todo
        },
        [
          full_row_button_subtext(
            outline.plus_circle(),
            h.text("Create new"),
            h.text("on this device"),
            Some(state.UserClickedSetupDevice),
          ),
        ],
      )
    Link ->
      layout(
        [
          h.img([
            a.src(
              "https://api.qrserver.com/v1/create-qr-code/?size=250x250&data=https://example.com",
            ),
          ]),
          h.div([], [h.text("Scan with trusted device.")]),
        ],
        [],
      )
  }
}

fn full_row_button(message, icon, text) {
  h.div(
    [
      event.on_click(message),
      a.class(
        "border-2 border-black border-dashed cover gap-3 hstack p-2 rounded-xl",
      ),
      a.styles([#("justify-content", "flex-start")]),
    ],
    [
      h.span(
        [
          a.class("w-12 p-2 rounded"),
          a.styles([
            #(
              "background",
              "linear-gradient(135deg, #a7f3d0 0%, #6ee7b7 25%, #34d399 50%, #10b981 75%, #059669 100%)",
            ),
          ]),
        ],
        [icon],
      ),
      h.span([], [h.text(text)]),
    ],
  )
}

fn full_row_button_subtext(icon, text, subtext, action) {
  h.div(
    [
      a.class(
        "border-2 border-black border-dashed cover gap-3 hstack p-2 rounded-xl",
      ),
      a.styles([
        #("justify-content", "flex-start"),
        // needs to reset minheight incase only a single child
        #("min-height", "auto"),
      ]),
      ..case action {
        Some(action) -> [
          event.on_click(action),
        ]
        None -> []
      }
    ],
    [
      h.span(
        [
          a.class("w-14 p-2 rounded flex-shrink-0"),
          a.styles([
            #(
              "background",
              "linear-gradient(135deg, #a7f3d0 0%, #6ee7b7 25%, #34d399 50%, #10b981 75%, #059669 100%)",
            ),
          ]),
        ],
        [icon],
      ),
      h.div([a.class("expand min-w-0")], [
        h.div([a.class("font-bold")], [text]),
        h.div([a.class("text-gray-600 overflow-hidden overflow-ellipsis")], [
          subtext,
        ]),
      ]),
    ],
  )
}

fn layout(children, footer) {
  h.div([a.class(" circles")], [
    h.style([], circles),
    h.style([], shimmer),
    h.div([a.class("circle")], []),
    h.div([a.class("circle")], []),
    h.div([a.class("circle")], []),
    h.div([a.class("circle")], []),
    h.div([a.class("circle")], []),
    h.div([a.class("circle")], []),

    // background: #f6f0ffd6;
    // z-index: 1;
    // width: 80%;
    // border-radius: 12px;
    h.div(
      [
        a.class("vstack max-w-2xl mx-auto neo-shadow border border-black"),
        a.styles([
          #("position", "absolute"),
          #("inset", "1.5em"),
          #("background", "#f6f0ffd6"),
          #("border-radius", "12px"),
        ]),
      ],
      [
        h.div([a.class("cover px-8 py-4 font-bold text-3xl")], [
          h.span(
            [
              a.styles([
                #("color", "#34d399"),
              ]),
            ],
            [h.text("EYG")],
          ),
          h.span([], [h.text(" ID")]),
        ]),
        h.div(
          [
            a.class("expand vstack cover mx-6 gap-2"),
            a.styles([
              #("justify-content", "flex-start"),
              // #("background", "#f6f0ffd6"),
            // #("z-index", "1"),
            // #("width", "80%"),
            // #("border-radius", "12px"),
            ]),
          ],
          children,
        ),
        h.div([a.class("cover mx-6 mb-4")], footer),
      ],
    ),
  ])
}

const shimmer = "
  .shimmer {
    background-color: #e2e5e7;
    background-image: linear-gradient(
      90deg, 
      rgba(255, 255, 255, 0) 0, 
      rgba(63, 63, 63, 0.5) 50%, 
      rgba(255, 255, 255, 0) 100%
    );
    background-size: 200% 100%;
    animation: shimmer 3.5s infinite linear;
    border-radius: 4px;
  }
  .skeleton-line {
    height: 14px;
    width: 80%;
    margin: 8px
  }

  .skeleton-line.short {
    width: 50%;
  }

  @keyframes shimmer {
    0% { background-position: -200% 0; }
    100% { background-position: 200% 0; }
  }
"

const circles = "    
        .circles {
            margin: 0;
            padding: 0;
            width: 100%;
            height: 100%;
            position: relative;
            overflow: hidden;
            background: linear-gradient(135deg, #a7f3d0 0%, #6ee7b7 25%, #34d399 50%, #10b981 75%, #059669 100%);
        }
        
        .circle {
            position: absolute;
            border-radius: 50%;
            opacity: 0.6;
            animation: float 20s infinite ease-in-out;
        }
        
        .circle:nth-child(1) {
            width: 300px;
            height: 300px;
            background: linear-gradient(135deg, #d1fae5, #6ee7b7);
            top: 10%;
            left: 15%;
            animation-delay: 0s;
        }
        
        .circle:nth-child(2) {
            width: 200px;
            height: 200px;
            background: linear-gradient(180deg, #a7f3d0, #34d399);
            top: 50%;
            left: 70%;
            animation-delay: -5s;
        }
        
        .circle:nth-child(3) {
            width: 250px;
            height: 250px;
            background: linear-gradient(90deg, #6ee7b7, #10b981);
            top: 60%;
            left: 20%;
            animation-delay: -10s;
        }
        
        .circle:nth-child(4) {
            width: 180px;
            height: 180px;
            background: linear-gradient(45deg, #34d399, #059669);
            top: 20%;
            left: 60%;
            animation-delay: -15s;
        }
        
        .circle:nth-child(5) {
            width: 220px;
            height: 220px;
            background: linear-gradient(270deg, #d1fae5, #a7f3d0);
            top: 70%;
            left: 50%;
            animation-delay: -7s;
        }
        
        .circle:nth-child(6) {
            width: 160px;
            height: 160px;
            background: linear-gradient(225deg, #10b981, #6ee7b7);
            top: 35%;
            left: 40%;
            animation-delay: -12s;
        }
        
        "
// @keyframes float {
//     0%, 100% {
//         transform: translate(0, 0) scale(1);
//     }
//     33% {
//         transform: translate(30px, -30px) scale(1.1);
//     }
//     66% {
//         transform: translate(-20px, 20px) scale(0.9);
//     }
// }
