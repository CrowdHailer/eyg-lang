import glasshouse/archive
import glasshouse/context
import glasshouse/diff
import glasshouse/journal
import glasshouse/langfuse
import glasshouse/rerun
import glasshouse/run
import glasshouse/session
import glasshouse/timeline
import glasshouse/value
import gleam/dict
import gleam/dynamic/decode
import gleam/int
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string
import lustre/attribute as a
import lustre/element.{type Element}
import lustre/element/html as h
import lustre/event
import plinth/browser/file.{type File}
import plinthx/browser/input
import website/components
import website/routes/glasshouse/debugger/state.{
  type Model, type Moment, type Trace, Compare, Replay, Step,
}
import website/routes/glasshouse/layout

pub fn view(model: Model) -> Element(state.Message) {
  h.div([a.class("gh-debugger")], [
    components.header(),
    layout.nav("/glasshouse/debugger"),
    toolbar(model),
    case state.active(model) {
      Ok(trace) -> workspace(model, trace)
      Error(Nil) -> empty(model)
    },
  ])
}

fn empty(model: Model) {
  h.div([a.class("gh-empty")], [
    case model.loading, model.error {
      _, Some(reason) -> h.p([a.class("gh-error")], [element.text(reason)])
      [_, ..], None -> h.p([], [element.text("Loading the demo session…")])
      [], None ->
        h.p([], [
          element.text("Open a trace saved by the eyg CLI to explore it."),
        ])
    },
  ])
}

// Toolbar ----------------------------------------------------------------------

fn toolbar(model: Model) {
  h.div([a.class("gh-toolbar")], [
    h.div(
      [a.class("gh-traces"), a.role("tablist")],
      list.flatten([
        list.index_map(model.traces, fn(trace, i) {
          let active = i == state.active_index(model)
          h.button(
            [
              a.class("gh-trace"),
              a.classes([#("gh-trace-active", active)]),
              a.role("tab"),
              a.attribute("aria-selected", bool(active)),
              event.on_click(state.UserSelectedTrace(i)),
            ],
            [element.text(trace.name)],
          )
        }),
        [
          h.label([a.class("gh-trace gh-open")], [
            element.text("Open trace…"),
            h.input([
              a.type_("file"),
              a.accept([".json", "application/json"]),
              a.class("gh-hidden"),
              event.on("change", chosen_file()),
            ]),
          ]),
        ],
      ]),
    ),
    case state.active(model) {
      Ok(trace) -> meta(trace)
      Error(Nil) -> element.none()
    },
    case model.error {
      Some(reason) -> h.p([a.class("gh-error")], [element.text(reason)])
      None -> element.none()
    },
  ])
}

fn bool(value) {
  case value {
    True -> "true"
    False -> "false"
  }
}

fn chosen_file() {
  use event <- decode.then(decode.dynamic)
  case event_file(event) {
    Ok(file) -> decode.success(state.UserChoseFile(file))
    Error(Nil) -> decode.failure(state.UserClosedFile, "a chosen file")
  }
}

fn event_file(event: decode.Dynamic) -> Result(File, Nil) {
  input.event_file(event)
}

fn meta(trace: Trace) {
  let session = trace.archive.session
  let #(live, recorded) = session.usage(session)
  let agent = case session.agent {
    Some(agent) -> agent.provider <> " · " <> agent.model
    None -> "no agent"
  }
  h.div([a.class("gh-meta")], [
    h.span([a.class("gh-mono")], [element.text(session.id)]),
    h.span([], [element.text(agent)]),
    h.span([], [
      element.text(int.to_string(live.input + live.output) <> " tokens"),
      case recorded.input + recorded.output {
        0 -> element.none()
        saved ->
          h.span([a.class("gh-saved")], [
            element.text(" · " <> int.to_string(saved) <> " replayed"),
          ])
      },
    ]),
    ..list.flatten([
      list.map(trace.archive.links, fn(link) {
        let archive.Langfuse(host:, trace_id:) = link
        h.a(
          [
            a.class("gh-button"),
            a.href(langfuse.trace_url(host, trace_id)),
            a.target("_blank"),
          ],
          [element.text("Langfuse")],
        )
      }),
      [
        h.button(
          [a.class("gh-button"), event.on_click(state.UserClickedDownload)],
          [element.text("Download")],
        ),
      ],
    ])
  ])
}

// Workspace --------------------------------------------------------------------

fn workspace(model: Model, trace: Trace) {
  case model.panel {
    // Comparing is about whole traces, it has the full width.
    Compare ->
      h.div([a.class("gh-body")], [
        h.div([a.class("gh-workspace gh-workspace-wide")], [
          h.main([a.class("gh-detail")], [panel_tabs(model), compare(model)]),
        ]),
      ])
    _ ->
      h.div([a.class("gh-body")], [
        h.div([a.class("gh-workspace")], [
          h.aside([a.class("gh-timeline")], timeline(model, trace)),
          h.main([a.class("gh-detail")], [
            panel_tabs(model),
            case model.panel {
              Replay -> replay(trace)
              _ -> step(model, trace)
            },
          ]),
          h.aside([a.class("gh-files")], files(model, trace)),
        ]),
        scrubber(model, trace),
      ])
  }
}

fn panel_tabs(model: Model) {
  h.div(
    [a.class("gh-tabs"), a.role("tablist")],
    list.map(
      [#(Step, "Step"), #(Replay, "Replay"), #(Compare, "Compare variants")],
      fn(entry) {
        let #(panel, label) = entry
        h.button(
          [
            a.class("gh-tab"),
            a.classes([#("gh-tab-active", panel == model.panel)]),
            a.role("tab"),
            event.on_click(state.UserOpenedPanel(panel)),
          ],
          [element.text(label)],
        )
      },
    ),
  )
}

fn scrubber(model: Model, trace: Trace) {
  let count = list.length(trace.moments)
  h.div([a.class("gh-scrubber")], [
    h.button(
      [
        a.class("gh-button"),
        a.attribute("aria-label", "Previous moment"),
        event.on_click(state.UserSelectedMoment(model.moment - 1)),
      ],
      [element.text("←")],
    ),
    h.input([
      a.type_("range"),
      a.class("gh-range"),
      a.min("0"),
      a.max(int.to_string(int.max(count - 1, 0))),
      a.value(int.to_string(model.moment)),
      a.attribute("aria-label", "Moment in the session"),
      event.on_input(state.UserMovedScrubber),
    ]),
    h.button(
      [
        a.class("gh-button"),
        a.attribute("aria-label", "Next moment"),
        event.on_click(state.UserSelectedMoment(model.moment + 1)),
      ],
      [element.text("→")],
    ),
    h.span([a.class("gh-position")], [
      element.text(
        "moment "
        <> int.to_string(model.moment + 1)
        <> " of "
        <> int.to_string(count),
      ),
    ]),
  ])
}

// Timeline ---------------------------------------------------------------------

fn timeline(model: Model, trace: Trace) -> List(Element(state.Message)) {
  let #(rows, _) =
    list.index_fold(trace.moments, #([], ""), fn(acc, moment, i) {
      let #(rows, run) = acc
      let #(header, run) = case moment {
        state.Effect(frame) if frame.run != run -> #(
          [run_header(trace, frame)],
          frame.run,
        )
        state.Effect(frame) -> #([], frame.run)
        _ -> #([], "")
      }
      let row = moment_row(trace, moment, i, i == model.moment)
      #(list.append(rows, list.append(header, [row])), run)
    })
  [h.div([a.class("gh-heading")], [element.text("Timeline")]), ..rows]
}

fn run_header(trace: Trace, frame: timeline.Frame) {
  let origin = case
    list.find(session.runs(trace.archive.session), fn(r) { r.id == frame.run })
  {
    Ok(run.Run(origin: run.File(path:), ..)) ->
      " · " <> state.display_path(trace, path)
    _ -> ""
  }
  h.div([a.class("gh-run")], [
    element.text(state.run_label(trace, frame) <> origin),
  ])
}

fn moment_row(trace: Trace, moment: Moment, index: Int, selected: Bool) {
  let content = case moment {
    state.Effect(frame) -> [
      h.span([a.class("gh-index")], [element.text(int.to_string(frame.index))]),
      h.span([a.class("gh-label")], [element.text(frame.entry.label)]),
      h.span([a.class("gh-subject")], [
        element.text(timeline.subject(
          frame.entry,
          trace.archive.session.cwd,
          trace.archive.store,
        )),
      ]),
      answer_badge(frame.entry.answer),
      change_mark(frame),
    ]
    state.Prompted(text:, ..) -> [
      h.span([a.class("gh-who gh-who-user")], [element.text("User")]),
      h.span([a.class("gh-subject")], [element.text(preview(text, 60))]),
    ]
    state.Completed(generation:, ..) -> [
      h.span([a.class("gh-who gh-who-model")], [element.text("Model")]),
      h.span([a.class("gh-subject")], [
        element.text(case generation.error, generation.tool_calls {
          Some(reason), _ -> "failed: " <> preview(reason, 40)
          None, [] -> preview(generation.content, 44)
          None, calls ->
            int.to_string(list.length(calls))
            <> " tool call"
            <> plural(list.length(calls))
        }),
      ]),
      h.span([a.class("gh-tokens")], [
        element.text(tokens(generation.usage)),
      ]),
      source_badge(generation.source),
    ]
    state.Returned(call_id:, text:, ..) -> [
      h.span([a.class("gh-who gh-who-tool")], [element.text("Result")]),
      h.span([a.class("gh-subject")], [
        element.text(call_id <> " " <> preview(text, 44)),
      ]),
    ]
  }
  h.button(
    [
      a.id("moment-" <> int.to_string(index)),
      a.class("gh-moment"),
      a.classes([#("gh-selected", selected)]),
      event.on_click(state.UserSelectedMoment(index)),
    ],
    content,
  )
}

fn plural(count) {
  case count {
    1 -> ""
    _ -> "s"
  }
}

fn tokens(usage: session.Usage) {
  int.to_string(usage.input) <> " → " <> int.to_string(usage.output)
}

pub fn answer_badge(answer: journal.Answer) {
  let name = journal.answer_to_string(answer)
  h.span([a.class("gh-badge gh-answer-" <> name)], [element.text(name)])
}

fn source_badge(source: session.Source) {
  case source {
    session.Live ->
      h.span([a.class("gh-badge gh-live")], [element.text("live")])
    session.Recorded ->
      h.span([a.class("gh-badge gh-replayed")], [element.text("replayed")])
  }
}

fn change_mark(frame: timeline.Frame) {
  case frame.change {
    Some(timeline.Cloned(commit:, ..))
    | Some(timeline.Committed(commit:, ..)) ->
      h.span([a.class("gh-delta gh-mono")], [
        element.text(string.slice(commit, 0, 7)),
      ])
    Some(change) ->
      case timeline.change_diff(change), timeline.is_modification(change) {
        Some(edits), True -> {
          let #(added, removed) = diff.stats(edits)
          h.span([a.class("gh-delta")], [
            h.span([a.class("gh-added")], [
              element.text("+" <> int.to_string(added)),
            ]),
            element.text(" "),
            h.span([a.class("gh-removed")], [
              element.text("-" <> int.to_string(removed)),
            ]),
          ])
        }
        _, _ -> element.none()
      }
    None -> element.none()
  }
}

// Step -------------------------------------------------------------------------

fn step(model: Model, trace: Trace) {
  case state.current(model) {
    Ok(#(_, moment)) ->
      h.div([a.class("gh-step")], case moment {
        state.Effect(frame) -> effect(trace, frame)
        state.Prompted(text:, ..) -> [
          title("Prompt", "from the user"),
          message_bubble("user", "User", text),
        ]
        state.Completed(event:, generation:) ->
          generation_detail(trace, event, generation)
        state.Returned(call_id:, text:, ..) -> [
          title("Tool result", "returned to the model for " <> call_id),
          h.pre([a.class("gh-pre")], [element.text(text)]),
        ]
      })
    Error(Nil) -> element.none()
  }
}

fn title(text, subtitle) {
  h.div([a.class("gh-title")], [
    h.h2([], [element.text(text)]),
    h.p([], [element.text(subtitle)]),
  ])
}

fn effect(trace: Trace, frame: timeline.Frame) -> List(Element(state.Message)) {
  let entry = frame.entry
  let store = trace.archive.store
  list.flatten([
    [
      h.div([a.class("gh-title")], [
        h.h2([], [
          element.text(
            "Effect " <> int.to_string(frame.index) <> " · " <> entry.label,
          ),
        ]),
        h.p([], [
          element.text(state.run_label(trace, frame) <> " · "),
          answer_badge(entry.answer),
          element.text(" · " <> int.to_string(entry.duration) <> "ms"),
        ]),
      ]),
    ],
    case entry.path {
      Some(path) -> [field("Path", h.code([], [element.text(path)]))]
      None -> []
    },
    [
      field("Request", value_block(entry.lift, store)),
      field("Reply", value_block(entry.reply, store)),
    ],
    case entry.answer {
      journal.Altered(sent:) -> [
        h.p([a.class("gh-note")], [
          element.text(
            "The policy changed this request before it was sent, i.e. to add a credential. Only a fingerprint of what was sent is recorded: ",
          ),
          h.code([], [element.text(sent)]),
        ]),
      ]
      _ -> []
    },
    change_detail(trace, frame),
  ])
}

fn field(label, content) {
  h.div([a.class("gh-field")], [
    h.div([a.class("gh-field-label")], [element.text(label)]),
    content,
  ])
}

fn value_block(encoded, store) {
  h.pre([a.class("gh-pre")], [
    element.text(value.summary(encoded, store, 6000)),
  ])
}

fn change_detail(trace: Trace, frame: timeline.Frame) {
  case frame.change {
    Some(timeline.Cloned(url:, commit:, ..)) -> [
      h.p([a.class("gh-note")], [
        element.text("Cloned "),
        h.code([], [element.text(url)]),
        element.text(" at commit "),
        h.code([], [element.text(commit)]),
        element.text(
          ". The URL and commit point to every file in the clone, none are stored.",
        ),
      ]),
    ]
    Some(timeline.Committed(commit:, ..)) -> [
      h.p([a.class("gh-note")], [
        element.text("Committed every change, the new commit is "),
        h.code([], [element.text(commit)]),
        element.text("."),
      ]),
    ]
    Some(change) ->
      case timeline.change_diff(change), timeline.is_modification(change) {
        Some(edits), True -> [
          field(
            "Change to "
              <> state.display_path(trace, timeline.change_path(change)),
            diff_block(edits),
          ),
        ]
        _, _ -> []
      }
    None -> []
  }
}

pub fn diff_block(edits: List(diff.Edit)) {
  h.div(
    [a.class("gh-diff")],
    diff.hunks(edits, 3)
      |> list.flat_map(fn(hunk) {
        [
          h.div([a.class("gh-hunk")], [
            element.text(
              "@@ -"
              <> int.to_string(hunk.old_start)
              <> " +"
              <> int.to_string(hunk.new_start)
              <> " @@",
            ),
          ]),
          ..list.map(hunk.edits, fn(edit) {
            case edit {
              diff.Keep(line) ->
                h.div([a.class("gh-line")], [element.text("  " <> line)])
              diff.Insert(line) ->
                h.div([a.class("gh-line gh-line-added")], [
                  element.text("+ " <> line),
                ])
              diff.Delete(line) ->
                h.div([a.class("gh-line gh-line-removed")], [
                  element.text("- " <> line),
                ])
            }
          })
        ]
      }),
  )
}

fn generation_detail(
  trace: Trace,
  event: Int,
  generation: session.Generation,
) -> List(Element(state.Message)) {
  let messages = context.before(trace.archive.session, event)
  let model = case trace.archive.session.agent {
    Some(agent) -> agent.model
    None -> "model"
  }
  list.flatten([
    [
      h.div([a.class("gh-title")], [
        h.h2([], [element.text("Generation " <> generation.id)]),
        h.p([], [
          element.text(
            model <> " · " <> tokens(generation.usage) <> " tokens · ",
          ),
          source_badge(generation.source),
          element.text(
            " · "
            <> int.to_string(generation.ended - generation.started)
            <> "ms",
          ),
        ]),
      ]),
    ],
    case generation.source {
      session.Recorded -> [
        h.p([a.class("gh-note")], [
          element.text(
            "The request was identical to one in the recorded session, the recorded completion was used and no tokens were spent.",
          ),
        ]),
      ]
      session.Live -> []
    },
    [
      h.details([a.class("gh-context")], [
        h.summary([], [
          element.text(
            "Context the model saw, "
            <> int.to_string(list.length(messages))
            <> " message"
            <> plural(list.length(messages)),
          ),
        ]),
        ..list.map(messages, context_message)
      ]),
      h.div([a.class("gh-field-label")], [element.text("Reply")]),
    ],
    case generation.error {
      Some(reason) -> [h.p([a.class("gh-error")], [element.text(reason)])]
      None -> []
    },
    case generation.thinking {
      "" -> []
      thinking -> [message_bubble("thinking", "Thinking", thinking)]
    },
    case generation.content {
      "" -> []
      content -> [message_bubble("assistant", "Assistant", content)]
    },
    list.map(generation.tool_calls, tool_call),
  ])
}

fn context_message(message: context.Message) {
  case message {
    context.System(text) -> message_bubble("system", "System", text)
    context.User(text) -> message_bubble("user", "User", text)
    context.Assistant(thinking: _, text:, tool_calls:) ->
      h.div([], [
        case text {
          "" -> element.none()
          text -> message_bubble("assistant", "Assistant", text)
        },
        ..list.map(tool_calls, tool_call)
      ])
    context.Tool(call_id:, text:) ->
      message_bubble("tool", "Result " <> call_id, text)
  }
}

fn message_bubble(kind, label, text) {
  h.div([a.class("gh-message gh-message-" <> kind)], [
    h.div([a.class("gh-message-label")], [element.text(label)]),
    h.pre([a.class("gh-message-text")], [element.text(text)]),
  ])
}

fn tool_call(call: session.ToolCall) {
  let code =
    json.parse(
      call.arguments,
      decode.field("code", decode.string, decode.success),
    )
  h.div([a.class("gh-message gh-message-call")], [
    h.div([a.class("gh-message-label")], [
      element.text("Calls " <> call.name <> " · " <> call.id),
    ]),
    h.pre([a.class("gh-code")], case code {
      Ok(code) -> highlight(code)
      Error(_) -> [element.text(call.arguments)]
    }),
  ])
}

// Replay -----------------------------------------------------------------------

fn replay(trace: Trace) {
  h.div([a.class("gh-step")], [
    title(
      "Replay",
      "Run every program in the trace again, here in your browser, with each effect answered from the journal.",
    ),
    case trace.replay {
      None ->
        h.button(
          [
            a.class("gh-button gh-primary"),
            event.on_click(state.UserClickedReplay),
          ],
          [element.text("Replay " <> trace.name)],
        )
      Some(reports) -> {
        let failed = list.count(reports, fn(r) { r.problem != None })
        h.div([], [
          h.p([a.class("gh-replay-summary")], [
            element.text(case failed {
              0 ->
                "✓ "
                <> int.to_string(list.length(reports))
                <> " runs reproduced exactly."
              _ ->
                "✗ "
                <> int.to_string(failed)
                <> " of "
                <> int.to_string(list.length(reports))
                <> " runs differed."
            }),
          ]),
          h.ul(
            [a.class("gh-reports")],
            list.map(reports, fn(report) { replay_report(trace, report) }),
          ),
        ])
      }
    },
  ])
}

fn replay_report(trace: Trace, report: rerun.Report) {
  let name = case report.run.kind, report.run.origin {
    run.Config, run.File(path:) ->
      "configuration " <> state.display_path(trace, path)
    run.Config, _ -> "configuration"
    run.Tool(call_id), _ -> "tool call " <> call_id
    run.Cell, _ -> "shell input " <> report.run.id
    run.Script(..), _ | run.Block, _ -> "run " <> report.run.id
  }
  let effects =
    int.to_string(report.effects) <> " effect" <> plural(report.effects)
  case report.problem {
    None ->
      h.li([a.class("gh-report gh-report-ok")], [
        element.text("✓ " <> name <> " · " <> effects),
      ])
    Some(problem) ->
      h.li([a.class("gh-report gh-report-failed")], [
        element.text("✗ " <> name <> " · " <> effects),
        h.div([a.class("gh-note")], [
          element.text(rerun.describe(problem, trace.archive.store)),
        ]),
      ])
  }
}

// Compare ----------------------------------------------------------------------

fn compare(model: Model) {
  let summaries = state.cohort(model)
  let most =
    list.fold(summaries, 1, fn(most, s) {
      int.max(
        most,
        s.live.input + s.live.output + s.saved.input + s.saved.output,
      )
    })
  let cwd = case model.traces {
    [first, ..] -> first.archive.session.cwd
    [] -> "/"
  }
  h.div([a.class("gh-step")], [
    title(
      "Compare variants",
      "Every open trace, evaluated variants spend tokens only on completions the recording could not answer.",
    ),
    h.div([a.class("gh-table-scroll")], [
      h.table([a.class("gh-table")], [
        h.thead([], [
          h.tr(
            [],
            list.map(
              [
                "Trace", "Generations", "Replayed", "Tokens", "Tool calls",
                "Effects", "Files changed", "Result",
              ],
              fn(heading) { h.th([], [element.text(heading)]) },
            ),
          ),
        ]),
        h.tbody(
          [],
          list.index_map(summaries, fn(s, i) {
            let live = s.live.input + s.live.output
            let saved = s.saved.input + s.saved.output
            h.tr(
              [
                a.class("gh-row"),
                a.classes([#("gh-row-active", i == state.active_index(model))]),
                event.on_click(state.UserSelectedTrace(i)),
              ],
              [
                h.td([a.class("gh-strong")], [element.text(s.name)]),
                h.td([], [element.text(int.to_string(s.generations))]),
                h.td([], [element.text(int.to_string(s.recorded))]),
                h.td([], [
                  h.div([a.class("gh-bar")], [
                    h.span(
                      [
                        a.class("gh-bar-live"),
                        a.style("width", percent(live, most)),
                      ],
                      [],
                    ),
                    h.span(
                      [
                        a.class("gh-bar-saved"),
                        a.style("width", percent(saved, most)),
                      ],
                      [],
                    ),
                  ]),
                  h.div([a.class("gh-small")], [
                    element.text(int.to_string(live) <> " spent"),
                    case saved {
                      0 -> element.none()
                      _ ->
                        h.span([a.class("gh-saved")], [
                          element.text(", " <> int.to_string(saved) <> " saved"),
                        ])
                    },
                  ]),
                ]),
                h.td([], [element.text(int.to_string(s.tool_calls))]),
                h.td([], [element.text(int.to_string(s.effects))]),
                h.td(
                  [],
                  list.map(s.changes, fn(change) {
                    h.div([a.class("gh-small")], [
                      element.text(timeline.relative(change.path, cwd) <> " "),
                      h.span([a.class("gh-added")], [
                        element.text("+" <> int.to_string(change.added)),
                      ]),
                      element.text(" "),
                      h.span([a.class("gh-removed")], [
                        element.text("-" <> int.to_string(change.removed)),
                      ]),
                    ])
                  }),
                ),
                h.td([a.class("gh-small")], [
                  case s.stopped {
                    Some(reason) ->
                      h.span([a.class("gh-stopped")], [
                        element.text("stopped: " <> reason),
                      ])
                    None -> element.text(preview(s.answer, 90))
                  },
                ]),
              ],
            )
          }),
        ),
      ]),
    ]),
    h.p([a.class("gh-note")], [
      h.span([a.class("gh-legend gh-bar-live")], []),
      element.text(" tokens spent "),
      h.span([a.class("gh-legend gh-bar-saved")], []),
      element.text(" tokens answered from the recording"),
    ]),
  ])
}

fn percent(part, whole) {
  int.to_string(part * 100 / whole) <> "%"
}

// Files ------------------------------------------------------------------------

type Tree {
  Folder(
    name: String,
    path: String,
    node: Option(timeline.Node),
    children: List(Tree),
  )
  Leaf(name: String, path: String, node: timeline.Node)
}

fn files(model: Model, trace: Trace) -> List(Element(state.Message)) {
  let known = state.files(model)
  let listing = timeline.listing(known)
  let changed = state.changed(model)
  let written = state.written(model)
  let cwd = trace.archive.session.cwd
  let tree =
    grow(
      list.map(listing, fn(entry) {
        let #(path, node) = entry
        let relative = timeline.relative(path, cwd)
        let segments = case relative == path {
          // Files outside the project are shown by their full path.
          True -> [path]
          False -> string.split(relative, "/")
        }
        #(segments, path, node)
      }),
      "",
    )
  list.flatten([
    [
      h.div([a.class("gh-heading")], [
        element.text("Files at this moment"),
        h.span([a.class("gh-count")], [
          element.text(int.to_string(list.length(listing))),
        ]),
      ]),
    ],
    case tree {
      [] -> [
        h.p([a.class("gh-note")], [
          element.text("No files have been read or written yet."),
        ]),
      ]
      _ -> [
        h.ul([a.class("gh-tree")], list.map(tree, branch(_, changed, written))),
      ]
    },
    case model.file {
      Some(path) -> [viewer(trace, path, dict.get(known, path))]
      None -> []
    },
  ])
}

fn grow(entries: List(#(List(String), String, timeline.Node)), prefix: String) {
  let names =
    list.filter_map(entries, fn(entry) { list.first(entry.0) })
    |> list.unique
  list.map(names, fn(name) {
    let group =
      list.filter(entries, fn(entry) { list.first(entry.0) == Ok(name) })
    let own =
      list.find_map(group, fn(entry) {
        case entry.0 {
          [_] -> Ok(#(entry.1, entry.2))
          _ -> Error(Nil)
        }
      })
    let deeper =
      list.filter_map(group, fn(entry) {
        case entry.0 {
          [_, next, ..rest] -> Ok(#([next, ..rest], entry.1, entry.2))
          _ -> Error(Nil)
        }
      })
    let path = case prefix {
      "" -> name
      _ -> prefix <> "/" <> name
    }
    case own, deeper {
      Ok(#(full, node)), [] -> Leaf(name:, path: full, node:)
      Ok(#(full, node)), _ ->
        Folder(
          name:,
          path: full,
          node: Some(node),
          children: grow(deeper, path),
        )
      Error(Nil), _ ->
        Folder(name:, path:, node: None, children: grow(deeper, path))
    }
  })
}

fn branch(tree: Tree, changed: Option(String), written: List(String)) {
  case tree {
    Folder(name:, node:, children:, ..) ->
      h.li([a.class("gh-folder")], [
        h.div([a.class("gh-folder-name")], [
          element.text(name <> "/"),
          case node {
            Some(timeline.Checkout(url:, commit:)) ->
              h.span([a.class("gh-badge gh-checkout")], [
                element.text(
                  "clone of " <> url <> " @ " <> string.slice(commit, 0, 7),
                ),
              ])
            _ -> element.none()
          },
        ]),
        h.ul([], list.map(children, branch(_, changed, written))),
      ])
    Leaf(name:, path:, node:) ->
      h.li([], [
        h.button(
          [
            a.class("gh-file"),
            a.classes([
              #("gh-file-changed", changed == Some(path)),
              #("gh-file-written", list.contains(written, path)),
            ]),
            event.on_click(state.UserSelectedFile(path)),
          ],
          [
            element.text(name),
            case changed == Some(path), node {
              True, _ ->
                h.span([a.class("gh-badge gh-now")], [element.text("changed")])
              _, timeline.Checkout(commit:, ..) ->
                h.span([a.class("gh-badge gh-checkout")], [
                  element.text("clone @ " <> string.slice(commit, 0, 7)),
                ])
              _, timeline.Directory ->
                h.span([a.class("gh-badge")], [element.text("directory")])
              _, _ ->
                case list.contains(written, path) {
                  True ->
                    h.span([a.class("gh-badge gh-written")], [
                      element.text("written"),
                    ])
                  False -> element.none()
                }
            },
          ],
        ),
      ])
  }
}

fn viewer(trace: Trace, path: String, node: Result(timeline.Node, Nil)) {
  let body = case node {
    Ok(timeline.File(content)) ->
      case content, timeline.text(content) {
        timeline.Whole(_), Some(text) -> [numbered(text)]
        timeline.Part(offset:, ..), Some(text) -> [
          h.p([a.class("gh-note")], [
            element.text(
              "Only part of this file was read, from byte "
              <> int.to_string(offset)
              <> ".",
            ),
          ]),
          numbered(text),
        ]
        timeline.Ending(_), Some(text) -> [
          h.p([a.class("gh-note")], [
            element.text("Only the end of this file, appended to, is known."),
          ]),
          numbered(text),
        ]
        timeline.Unseen(_), _ -> [
          h.p([a.class("gh-note")], [
            element.text("The file exists but its content was never seen."),
          ]),
        ]
        _, None -> [
          h.p([a.class("gh-note")], [element.text("The content is not text.")]),
        ]
      }
    Ok(timeline.Checkout(url:, commit:)) -> [
      h.p([a.class("gh-note")], [
        element.text("A clone of " <> url <> " at " <> commit <> "."),
      ]),
    ]
    Ok(timeline.Directory) -> [
      h.p([a.class("gh-note")], [element.text("A directory.")]),
    ]
    Ok(timeline.Absent) | Error(Nil) -> [
      h.p([a.class("gh-note")], [
        element.text("This file is not known at this moment."),
      ]),
    ]
  }
  h.div([a.class("gh-viewer")], [
    h.div([a.class("gh-viewer-head")], [
      h.span([a.class("gh-mono")], [
        element.text(state.display_path(trace, path)),
      ]),
      h.button(
        [
          a.class("gh-button"),
          a.attribute("aria-label", "Close file"),
          event.on_click(state.UserClosedFile),
        ],
        [element.text("×")],
      ),
    ]),
    ..body
  ])
}

fn numbered(text) {
  h.pre(
    [a.class("gh-numbered")],
    diff.split(text)
      |> list.index_map(fn(line, i) {
        h.span([a.class("gh-numbered-line")], [
          h.span([a.class("gh-line-number")], [
            element.text(int.to_string(i + 1)),
          ]),
          element.text(line <> "\n"),
        ])
      }),
  )
}

// Text -------------------------------------------------------------------------

/// One line of text shortened to a length.
pub fn preview(text: String, length: Int) -> String {
  let line =
    string.split(text, "\n")
    |> list.map(string.trim)
    |> list.filter(fn(line) { line != "" })
    |> string.join(" ")
  case string.length(line) > length {
    True -> string.slice(line, 0, length) <> "…"
    False -> line
  }
}

/// Colour EYG source: keywords, effects and tags, builtins, strings and comments.
pub fn highlight(code: String) -> List(Element(msg)) {
  tokens_of(string.to_graphemes(code), [])
  |> list.map(fn(token) {
    let #(class, text) = token
    case class {
      "" -> element.text(text)
      class -> h.span([a.class(class)], [element.text(text)])
    }
  })
}

fn tokens_of(chars: List(String), done: List(#(String, String))) {
  case chars {
    [] -> list.reverse(done)
    ["/", "/", ..] -> {
      let #(comment, rest) = take_until(chars, "\n", "")
      tokens_of(rest, [#("gh-c-comment", comment), ..done])
    }
    ["\"", ..rest] -> {
      let #(text, rest) = string_literal(rest, "")
      tokens_of(rest, [#("gh-c-string", text), ..done])
    }
    ["!", ..rest] -> {
      let #(word, rest) = take_word(rest, "")
      tokens_of(rest, [#("gh-c-builtin", "!" <> word), ..done])
    }
    [c, ..rest] ->
      case is_word(c) {
        True -> {
          let #(word, rest) = take_word(chars, "")
          let class = case word {
            "let" | "match" | "perform" | "handle" | "import" -> "gh-c-keyword"
            _ ->
              case string.contains(capitals, string.slice(word, 0, 1)) {
                True -> "gh-c-tag"
                False -> ""
              }
          }
          tokens_of(rest, [#(class, word), ..done])
        }
        False -> tokens_of(rest, [#("", c), ..done])
      }
  }
}

fn is_word(c) {
  string.contains(
    "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_",
    c,
  )
}

const capitals = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"

fn take_word(chars, word) {
  case chars {
    [c, ..rest] ->
      case is_word(c) {
        True -> take_word(rest, word <> c)
        False -> #(word, chars)
      }
    [] -> #(word, chars)
  }
}

fn take_until(chars, stop, taken) {
  case chars {
    [c, ..] if c == stop -> #(taken, chars)
    [c, ..rest] -> take_until(rest, stop, taken <> c)
    [] -> #(taken, [])
  }
}

fn string_literal(chars, text) {
  case chars {
    ["\\", c, ..rest] -> string_literal(rest, text <> "\\" <> c)
    ["\"", ..rest] -> #("\"" <> text <> "\"", rest)
    [c, ..rest] -> string_literal(rest, text <> c)
    [] -> #("\"" <> text, [])
  }
}
