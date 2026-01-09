import gleam/option.{None, Some}
import gleroglero/outline
import lustre/attribute as a
import lustre/element/html as h
import lustre/event
import website/routes/sign/state.{State}

pub fn model(state) {
  case state {
    // Look at the keys
    // State(opener: None, ..) -> Failed(message: "")
    State(keypairs: state.Fetching(..), ..) -> Loading
    State(keypairs: state.Failed(..), ..) -> todo
    State(keypairs: state.Fetched(..), ..) -> Setup
  }
}

pub type Model {
  Failed(message: String)
  Loading
  Setup
}

pub fn render(model) {
  case model {
    Failed(message:) -> layout([h.text("failed " <> message)])
    Loading -> layout([h.text("loading")])
    Setup ->
      layout([
        h.div([], [
          h.text("setup"),
        ]),
        h.div(
          [
            a.class("expand"),
            a.styles([
              #("background", "#f6f0ffd6"),
              #("z-index", "1"),
              #("width", "80%"),
              #("border-radius", "12px"),
            ]),
          ],
          [outline.key()],
        ),
        h.button([event.on_click(state.UserClickedCreateKey)], [
          h.text("Create key"),
        ]),
      ])
  }
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
    h.div([a.class("vstack"), a.styles([#("height", "100%")])], children),
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
