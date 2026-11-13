import gleam/dict
import gleam/int
import gleam/list
import gleam/option.{None, Some}
import gleam/set
import gleam/string
import lustre/attribute as a
import lustre/element
import lustre/element/html as h
import lustre/event
import oas/generator/utils
import overlay/llm/chat
import overlay/llm/tool
import overlay/public/cache_status
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
          h.div([a.class("session-settings")], [
            provider_view.render(model),
            render_context(view.context(model)),
            render_policy(model),
          ]),
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
      render_activity(model),
      case messages, model.status {
        [_, ..], state.Waiting ->
          h.div([a.class("chat-actions")], [
            action_button("Export", state.UserClickedExport),
            action_button("New chat", state.UserClickedNewChat),
          ])
        _, _ -> element.none()
      },
      cache_status.render(model),
      input.render(
        model.input,
        "Ask anything...",
        state.UserUpdatedInput,
        state.UserSubmittedPrompt,
        state.Ignore,
      ),
    ]),
    render_trace(view.trace(model)),
  ])
}

// Every effect of the session is recorded, the trace opens in the Glasshouse debugger.
fn render_trace(trace: #(String, List(view.Run))) {
  let #(id, runs) = trace
  h.aside([a.class("trace")], [
    h.div([a.class("trace-heading")], [
      h.h2([], [h.text("Trace")]),
      h.button(
        [
          a.class("button trace-download"),
          event.on_click(state.UserClickedDownloadTrace),
        ],
        [h.text("Download")],
      ),
    ]),
    h.p([a.class("trace-note")], [
      h.text("Every effect is recorded in " <> id <> ". "),
      h.text("Download the trace and open it in the "),
      h.a([a.href("https://eyg.run/glasshouse/debugger"), a.target("_blank")], [
        h.text("Glasshouse debugger"),
      ]),
      h.text(
        " to step through and replay it. The agent can read it with the Trace effect.",
      ),
    ]),
    case runs {
      [] -> h.p([a.class("trace-note")], [h.text("No tool calls yet.")])
      runs -> h.ol([a.class("trace-runs")], list.map(runs, render_run))
    },
  ])
}

fn render_run(run: view.Run) {
  let view.Run(id:, code:, effects:, result:) = run
  h.li([a.class("trace-run")], [
    h.div([a.class("trace-run-heading")], [
      h.span([a.class("trace-id")], [h.text(id)]),
      h.code([a.class("one-line")], [h.text(first_line(code))]),
    ]),
    case effects {
      [] -> element.none()
      effects ->
        h.ul(
          [a.class("trace-effects")],
          list.map(effects, fn(effect) {
            let #(label, summary) = effect
            h.li([], [
              h.span([a.class("trace-label")], [h.text(label)]),
              h.text(" " <> summary),
            ])
          }),
        )
    },
    h.div([a.class("trace-result one-line")], [
      h.text("→ " <> first_line(result)),
    ]),
  ])
}

fn render_context(context) {
  case context {
    view.Default -> element.none()
    view.Loading(name:) ->
      h.div([a.class("context loading")], [
        h.text("Loading context " <> name <> "..."),
      ])
    view.Loaded(name:, has_readme:) ->
      h.div([a.class("context ready")], [
        case has_readme {
          True -> context_dot("ready", "Context loaded with a readme.")
          False ->
            context_dot(
              "warning",
              "No readme. The agent receives default instructions and the module's type.",
            )
        },
        h.span([a.class("context-label"), a.title(name)], [
          h.text("Context " <> name),
        ]),
      ])
    view.Failed(name:, reason:) ->
      h.div([a.class("context failure-message")], [
        context_dot("failed", "Context unavailable: " <> reason),
        h.text(name <> ": " <> reason),
      ])
  }
}

fn context_dot(status, description) {
  h.span(
    [
      a.class("context-dot " <> status),
      a.title(description),
      a.attribute("role", "img"),
      a.attribute("aria-label", description),
    ],
    [],
  )
}

fn render_chat(message: #(Int, chat.Message(tool.Call)), expanded) {
  let #(index, message) = message
  let expand = set.contains(expanded, index)
  case message {
    // The user writes plain text, rendering it as markup would drop characters.
    chat.UserMessage(text:, images: _) -> [
      h.div([a.class("message user")], [h.text(text)]),
    ]
    chat.AssistantMessage(thinking:, text:, tool_calls:) -> {
      // Models often write markdown, `**bold**` is `*bold*` in djot.
      let #(_front, doc) = pamphlet.parse(string.replace(text, "**", "*"))
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
                  [h.text("Show the model's thinking")],
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
            [h.text(view.summary(text))],
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

/// What the agent is doing, with a button to stop it.
fn render_activity(model: state.State) {
  let activity = case model.status {
    state.Waiting -> None
    state.Asking(..) -> Some("Waiting for the model")
    state.Streaming(..) -> Some("The model is replying")
    state.Executing(..) -> Some("Running code")
  }
  case activity {
    None -> element.none()
    Some(activity) ->
      h.div([a.class("activity")], [
        h.span([a.class("activity-label")], [
          h.text(activity <> ", step " <> int.to_string(model.steps + 1)),
        ]),
        h.button(
          [
            a.class("stop"),
            a.type_("button"),
            event.on_click(state.UserClickedStop),
          ],
          [h.text("Stop")],
        ),
      ])
  }
}

/// The policy decides which effects the agent's code may perform.
fn render_policy(model: state.State) {
  let status = case model.policy {
    None -> "No policy, every effect is allowed"
    Some(_) -> "Policy applied"
  }
  h.details([a.class("policy")], [
    h.summary([], [h.text(status)]),
    h.p([], [
      h.text(
        "A record with a function for each effect the agent may use, returning Pass(value) or Mock(value).",
      ),
    ]),
    h.textarea(
      [
        a.class("policy-source"),
        a.placeholder(
          "{fetch: (request) -> { Pass(request) }, print: (text) -> { Pass(text) }}",
        ),
        a.rows(6),
        event.on_input(state.UserUpdatedPolicy),
      ],
      model.policy_source,
    ),
    h.button([a.type_("button"), event.on_click(state.UserAppliedPolicy)], [
      h.text("Apply policy"),
    ]),
    case model.policy_error {
      Some(reason) -> h.pre([a.class("failure-message")], [h.text(reason)])
      None -> element.none()
    },
  ])
}

fn action_button(label, message) {
  h.button(
    [a.class("chat-action"), a.type_("button"), event.on_click(message)],
    [h.text(label)],
  )
}
