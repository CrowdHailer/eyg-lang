import gleroglero/outline
import lustre/attribute as a
import lustre/element/html as h
import lustre/event
import website/routes/sign/state.{State}

pub fn model(state) {
  case state {
    // Look at the keys
    // State(opener: None, ..) -> Failed(message: "")
    // State(keypairs: state.Fetching(..), ..) -> Loading
    // State(keypairs: state.Failed(..), ..) -> todo
    // State(keypairs: state.Fetched(..), ..) -> Setup
    _ -> Setup
  }
}

pub type Model {
  Failed(message: String)
  Loading
  Setup
  Confirm
  Choose(keys: List(String))
  Link
}

pub fn render(model) {
  case model {
    Failed(message:) -> layout([h.text("failed " <> message)])
    Loading -> layout([h.text("loading")])
    Setup ->
      layout([
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
      ])
    Confirm ->
      layout([
        h.div([a.class("cover bg-white p-2")], [
          h.dl([], [
            h.dt([a.class("font-bold italic")], [h.text("type")]),
            h.dd([a.class("ml-8 mb-2")], [h.text("publish release")]),
            h.dt([a.class("font-bold italic")], [h.text("package")]),
            h.dd([a.class("ml-8 mb-2")], [h.text("standard")]),
            h.dt([a.class("font-bold italic")], [h.text("version")]),
            h.dd([a.class("ml-8 mb-2")], [h.text("2")]),
            h.dt([a.class("font-bold italic")], [h.text("module")]),
            h.dd([a.class("ml-8 mb-2")], [h.text("cadcdac23rgw45ur67ndfgdgw4")]),
          ]),
        ]),
        full_row_button(
          state.UserClickedSignPayload,
          outline.cloud_arrow_up(),
          "Sign",
        ),
      ])
    Choose(..) ->
      layout([
        full_row_button_subtext(
          outline.key(),
          "Personal account",
          "ab:1s:dx:3s:27",
        ),
        full_row_button_subtext(outline.key(), "EYG account", "ab:1s:dx:3s:27"),
        full_row_button_subtext(outline.key(), "Peter @ work", "ab:1s:dx:3s:27"),
      ])
    Link ->
      layout([
        h.img([
          a.src(
            "https://api.qrserver.com/v1/create-qr-code/?size=250x250&data=https://example.com",
          ),
        ]),
        h.div([], [h.text("Scan with trusted device.")]),
      ])
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

fn full_row_button_subtext(icon, text, subtext) {
  h.div(
    [
      a.class(
        "border-2 border-black border-dashed cover gap-3 hstack p-2 rounded-xl",
      ),
      a.styles([#("justify-content", "flex-start")]),
    ],
    [
      h.span(
        [
          a.class("w-14 p-2 rounded"),
          a.styles([
            #(
              "background",
              "linear-gradient(135deg, #a7f3d0 0%, #6ee7b7 25%, #34d399 50%, #10b981 75%, #059669 100%)",
            ),
          ]),
        ],
        [icon],
      ),
      h.div([], [
        h.div([a.class("font-bold")], [h.text(text)]),
        h.div([a.class("text-gray-600")], [h.text(subtext)]),
      ]),
    ],
  )
}

fn layout(children) {
  h.div([a.class(" circles")], [
    h.style([], circles),
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
        h.div([a.class("cover p-6 font-bold text-3xl absolute top-0")], [
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
            a.class("expand vstack cover mx-6 gap-6"),
            a.styles([
              // #("background", "#f6f0ffd6"),
            // #("z-index", "1"),
            // #("width", "80%"),
            // #("border-radius", "12px"),
            ]),
          ],
          children,
        ),
      ],
    ),
  ])
}

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
