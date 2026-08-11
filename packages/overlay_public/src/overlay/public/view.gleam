import gleam/dict
import gleam/list
import gleam/option.{None, Some}
import gleam/set
import lustre/attribute as a
import lustre/element
import lustre/element/html as h
import lustre/event
import oas/generator/utils
import overlay/llm/chat
import overlay/llm/tool
import overlay/public/input
import overlay/public/provider_setup as provider_view
import overlay/web/state
import overlay/web/view
import pamphlet
import pamphlet/lustre
import splitter

pub fn render(model: state.State) {
  // let state = demo()
  let messages = view.messages(model)
  h.div([a.class("layout")], [
    h.div([a.class("chat")], [
      h.header(
        [
          a.class("heading"),
          a.classes([#("hero", list.is_empty(messages))]),
        ],
        [
          h.h1([a.class("impact-heading")], [h.text("Overlay")]),
          provider_view.render(model),
        ],
      ),
      case messages {
        [] -> element.none()
        history ->
          h.div(
            [a.class("messages")],
            list.flat_map(history, render_chat(_, model.expanded)),
          )
      },
      case model.input_error {
        Some(error) -> h.div([a.class("failure-message")], [h.text(error)])
        None -> element.none()
      },
      input.render(
        model.input,
        "Ask anything...",
        state.UserUpdatedInput,
        state.UserSubmittedPrompt,
        state.Ignore,
      ),
    ]),
    // h.div([a.class("output")], [
  //   // h.div([], [h.span([], [h.text("cell1")])]),
  // // h.div([], [h.span([], [h.text("cell2")])]),
  // // h.div([], [h.span([], [h.text("cell3")])]),
  // // h.div([], [h.span([], [h.text("cell4")])]),
  // // h.div([], [h.span([], [h.text("cell5")])]),
  // ]),
  ])
}

fn render_chat(message: #(Int, chat.Message(tool.Call)), expanded) {
  let #(index, message) = message
  let expand = set.contains(expanded, index)
  case message {
    chat.UserMessage(text:, images: _) -> {
      let #(_front, doc) = pamphlet.parse(text)
      [
        h.div([a.class("message user")], [
          lustre.to_lustre(doc, lustre.default())(fn(x) { x }),
        ]),
      ]
    }
    chat.AssistantMessage(thinking:, text:, tool_calls:) -> {
      let #(_front, doc) = pamphlet.parse(text)
      [
        case thinking {
          "" -> element.none()
          _ ->
            case expand {
              False ->
                h.div(
                  [
                    a.class("message thinking"),
                    event.on_click(state.UserClickedExpand(index)),
                  ],
                  [h.text("thinking...")],
                )
              True ->
                h.div(
                  [
                    a.class("message thinking"),
                    event.on_click(state.UserClickedShrink(index)),
                  ],
                  [h.text(thinking)],
                )
            }
        },
        h.div([a.class("message assistant")], [
          lustre.to_lustre(doc, lustre.default())(fn(x) { x }),
        ]),
        ..list.map(tool_calls, fn(call) {
          let code = case dict.get(call.function.arguments, "code") {
            Ok(utils.String(code)) -> code
            _ -> ""
          }
          case expand {
            True ->
              h.div(
                [
                  a.class("message code"),
                  event.on_click(state.UserClickedShrink(index)),
                ],
                [
                  h.pre([], [h.code([], [h.text(code)])]),
                ],
              )
            False ->
              h.div(
                [
                  a.class("message code"),
                  event.on_click(state.UserClickedExpand(index)),
                ],
                [
                  h.pre([a.class("one-line")], [
                    h.code([], [h.text(first_line(code))]),
                  ]),
                ],
              )
          }
        })
      ]
      |> list.reverse
    }
    chat.ToolResultMessage(tool_call_id: _, text:, images: _) -> [
      case expand {
        True ->
          h.div(
            [
              a.class("message tool-result"),
              event.on_click(state.UserClickedShrink(index)),
            ],
            [h.text(text)],
          )
        False ->
          h.div(
            [
              a.class("message tool-result one-line"),
              event.on_click(state.UserClickedExpand(index)),
            ],
            [
              h.text(first_line(text)),
            ],
          )
      },
    ]
  }
}

fn first_line(text) {
  let #(pre, _, _) =
    splitter.new(["\r\n", "\n"])
    |> splitter.split(text)
  pre
}
