//// Export the observability half of a session as portable OpenTelemetry spans.
////
//// The session is a trace, generations and tool calls are observations and
//// every effect is an event under the run that performed it.
//// State is never uploaded, observations carry CIDs that point into the archive.
//// Spans are sent as OTLP JSON to `/api/public/otel/v1/traces`.

import glasshouse/context
import glasshouse/journal
import glasshouse/run.{type Run}
import glasshouse/session.{type Session}
import glasshouse/store.{type Sha256, type Store}
import glasshouse/value
import gleam/bit_array
import gleam/int
import gleam/json.{type Json}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import otel/clock
import otel/span as attribute
import otel/trace

pub type Span {
  Span(
    id: String,
    parent: Option(String),
    name: String,
    started: Int,
    ended: Int,
    attributes: List(#(String, attribute.Attribute)),
    error: Option(String),
  )
}

/// The OTLP trace id for a session, 32 hex characters.
pub fn trace_id(session: Session, sha256: Sha256) -> String {
  hex(sha256(<<"glasshouse/trace/":utf8, session.id:utf8>>), 16)
}

fn span_id(session: Session, key: String, sha256: Sha256) -> String {
  hex(
    sha256(<<"glasshouse/span/":utf8, session.id:utf8, "/":utf8, key:utf8>>),
    8,
  )
}

fn hex(digest: BitArray, bytes: Int) -> String {
  case bit_array.slice(digest, 0, bytes) {
    Ok(part) -> bit_array.base16_encode(part) |> string.lowercase
    Error(Nil) -> bit_array.base16_encode(digest) |> string.lowercase
  }
}

/// Every span for a session, the session's own span first.
pub fn spans(session: Session, store: Store, sha256: Sha256) -> List(Span) {
  let root = span_id(session, "session", sha256)
  let name = case session.agent {
    Some(_) -> "overlay session"
    None -> "eyg session"
  }
  let prompts =
    list.filter_map(session.events, fn(event) {
      case event {
        session.Prompt(text:, ..) -> Ok(text)
        _ -> Error(Nil)
      }
    })
  let answers =
    list.filter_map(session.generations(session), fn(g) {
      case g.content {
        "" -> Error(Nil)
        content -> Ok(content)
      }
    })
  let #(live, recorded) = session.usage(session)
  let session_span =
    Span(
      id: root,
      parent: None,
      name:,
      started: session.started,
      ended: session.ended,
      attributes: list.flatten([
        [
          #("langfuse.trace.name", text(name)),
          #("eyg.session.id", text(session.id)),
          #("langfuse.session.id", text(session.id)),
          #("langfuse.trace.tags", texts(["glasshouse"])),
          #("langfuse.trace.metadata.glasshouse_session", text(session.id)),
          #("langfuse.trace.metadata.cwd", text(session.cwd)),
          #(
            "langfuse.trace.metadata.tokens_live",
            integer(live.input + live.output),
          ),
          #(
            "langfuse.trace.metadata.tokens_replayed",
            integer(recorded.input + recorded.output),
          ),
          #(
            "langfuse.observation.type",
            text(case session.agent {
              Some(_) -> "agent"
              None -> "chain"
            }),
          ),
        ],
        case prompts {
          [first, ..] -> [#("langfuse.trace.input", text(first))]
          [] -> []
        },
        case list.last(answers) {
          Ok(last) -> [#("langfuse.trace.output", text(last))]
          Error(Nil) -> []
        },
        case session.agent {
          Some(agent) -> [
            #("langfuse.trace.metadata.model", text(agent.model)),
            #("langfuse.trace.metadata.provider", text(agent.provider)),
          ]
          None -> []
        },
      ]),
      error: None,
    )
  let results =
    list.filter_map(session.events, fn(event) {
      case event {
        session.ToolResult(call_id:, text:, ..) -> Ok(#(call_id, text))
        _ -> Error(Nil)
      }
    })
  let model = case session.agent {
    Some(agent) -> agent.model
    None -> ""
  }
  let events =
    list.index_map(session.events, fn(event, i) {
      case event {
        session.Generated(generation:) -> [
          generation_span(session, generation, model, root, store, sha256),
        ]
        session.Execution(run:) ->
          run_spans(session, run, root, results, store, sha256)
        session.Prompt(at:, text: prompt) -> [
          Span(
            id: span_id(session, "prompt/" <> int.to_string(i), sha256),
            parent: Some(root),
            name: "user prompt",
            started: at,
            ended: at,
            attributes: [
              #("langfuse.observation.type", text("event")),
              #("langfuse.observation.input", text(prompt)),
            ],
            error: None,
          ),
        ]
        session.ToolResult(..) -> []
      }
    })
    |> list.flatten
  [session_span, ..events]
}

fn generation_span(
  session,
  generation: session.Generation,
  model,
  root,
  store,
  sha256,
) {
  let session.Generation(
    id:,
    started:,
    ended:,
    key:,
    request:,
    response:,
    content:,
    tool_calls:,
    usage:,
    source:,
    error:,
    ..,
  ) = generation
  let input = case store.get_binary(store, request) {
    Ok(body) ->
      case context.from_request(body) {
        Ok(messages) -> json.to_string(json.array(messages, message_json))
        Error(_) -> ""
      }
    Error(_) -> ""
  }
  let output =
    json.object([
      #("content", json.string(content)),
      #(
        "tool_calls",
        json.array(tool_calls, fn(call) {
          json.object([
            #("id", json.string(call.id)),
            #("name", json.string(call.name)),
            #("arguments", json.string(call.arguments)),
          ])
        }),
      ),
    ])
    |> json.to_string
  Span(
    id: span_id(session, "generation/" <> id, sha256),
    parent: Some(root),
    name: "generation",
    started:,
    ended:,
    attributes: list.flatten([
      [
        #("langfuse.observation.type", text("generation")),
        #("gen_ai.request.model", text(model)),
        #("gen_ai.operation.name", text("chat")),
        #(
          "gen_ai.provider.name",
          text(case session.agent {
            Some(agent) -> agent.provider
            None -> ""
          }),
        ),
        #("gen_ai.usage.input_tokens", integer(usage.input)),
        #("gen_ai.usage.output_tokens", integer(usage.output)),
        #("langfuse.observation.input", text(input)),
        #("langfuse.observation.output", text(output)),
        #("langfuse.observation.metadata.request", text(request)),
        #("langfuse.observation.metadata.cache_key", text(key)),
        #(
          "langfuse.observation.metadata.source",
          text(case source {
            session.Live -> "live"
            session.Recorded -> "recorded"
          }),
        ),
      ],
      case response {
        Some(response) -> [
          #("langfuse.observation.metadata.response", text(response)),
        ]
        None -> []
      },
    ]),
    error:,
  )
}

fn message_json(message) {
  case message {
    context.System(text:) -> role("system", text)
    context.User(text:) -> role("user", text)
    context.Assistant(text:, tool_calls:, ..) ->
      json.object([
        #("role", json.string("assistant")),
        #("content", json.string(text)),
        #(
          "tool_calls",
          json.array(tool_calls, fn(call) {
            json.object([
              #("name", json.string(call.name)),
              #("arguments", json.string(call.arguments)),
            ])
          }),
        ),
      ])
    context.Tool(text:, ..) -> role("tool", text)
  }
}

fn role(role, content) {
  json.object([#("role", json.string(role)), #("content", json.string(content))])
}

fn run_spans(session, run: Run, root, results, store, sha256) {
  let id = span_id(session, "run/" <> run.id, sha256)
  let #(type_, name) = case run.kind {
    run.Tool(..) -> #("tool", "run")
    run.Config -> #("chain", "configuration")
    run.Script(..) -> #("chain", "script")
    run.Block -> #("chain", "run")
    run.Cell -> #("chain", "shell input")
  }
  let output = case run.kind {
    run.Tool(call_id:) ->
      list.key_find(results, call_id) |> result.unwrap(outcome_text(run, store))
    _ -> outcome_text(run, store)
  }
  let error = case run.outcome {
    run.Failed(reason:) | run.Rejected(reason:) -> Some(reason)
    _ -> None
  }
  let pointers =
    run.journal
    |> list.flat_map(fn(entry) {
      case entry.path {
        Some(path) ->
          list.map(
            list.append(
              value.references(entry.lift),
              value.references(entry.reply),
            ),
            fn(cid) { path <> "@" <> cid },
          )
        None -> []
      }
    })
    |> list.unique
  let run_span =
    Span(
      id:,
      parent: Some(root),
      name:,
      started: run.started,
      ended: run.ended,
      attributes: list.flatten([
        [
          #("langfuse.observation.type", text(type_)),
          #("langfuse.observation.input", text(run.code)),
          #("langfuse.observation.output", text(output)),
          #("langfuse.observation.metadata.run", text(run.id)),
          #("eyg.run.id", text(run.id)),
          #("langfuse.observation.metadata.cwd", text(run.cwd)),
          #(
            "langfuse.observation.metadata.effects",
            integer(list.length(run.journal)),
          ),
          #("langfuse.observation.metadata.files", texts(pointers)),
        ],
        case run.program {
          Some(program) -> [
            #("langfuse.observation.metadata.program", text(program)),
          ]
          None -> []
        },
      ]),
      error:,
    )
  let effects =
    list.index_map(run.journal, fn(entry, position) {
      Span(
        id: span_id(
          session,
          "run/" <> run.id <> "/" <> int.to_string(position),
          sha256,
        ),
        parent: Some(id),
        name: entry.label,
        started: entry.started,
        ended: entry.started + entry.duration,
        attributes: list.flatten([
          [
            #("langfuse.observation.type", text("event")),
            #("langfuse.observation.input", text(summary(entry.lift, store))),
            #("langfuse.observation.output", text(summary(entry.reply, store))),
            #(
              "langfuse.observation.metadata.answer",
              text(journal.answer_to_string(entry.answer)),
            ),
            #("langfuse.observation.metadata.position", integer(position)),
          ],
          case entry.path {
            Some(path) -> [#("langfuse.observation.metadata.path", text(path))]
            None -> []
          },
          case entry.answer {
            journal.Altered(sent:) -> [
              #("langfuse.observation.metadata.sent", text(sent)),
            ]
            _ -> []
          },
        ]),
        error: None,
      )
    })
  [run_span, ..effects]
}

fn outcome_text(run: Run, store) {
  case run.outcome {
    run.Returned(encoded) -> value.render(encoded, store)
    run.Finished -> ""
    run.Exited(status:) -> "exited " <> int.to_string(status)
    run.Failed(reason:) | run.Rejected(reason:) -> reason
  }
}

// Large values such as file contents are already in the archive, keep events small.
fn summary(encoded, store) {
  let rendered = value.render(encoded, store)
  case string.length(rendered) > 500 {
    True -> string.slice(rendered, 0, 500) <> "…"
    False -> rendered
  }
}

fn text(value: String) -> attribute.Attribute {
  attribute.Text(value)
}

fn texts(values: List(String)) -> attribute.Attribute {
  attribute.Array(list.map(values, attribute.Text))
}

fn integer(value: Int) -> attribute.Attribute {
  attribute.Integer(value)
}

/// Convert recorded milliseconds to the shared, exact OTLP time representation.
pub fn otel_spans(
  session: Session,
  store: Store,
  sha256: Sha256,
) -> List(attribute.Span) {
  let trace = trace_id(session, sha256)
  list.map(spans(session, store, sha256), fn(s) {
    attribute.Span(
      trace_id: trace,
      span_id: s.id,
      parent_id: s.parent,
      name: s.name,
      started: clock.from_milliseconds(s.started),
      ended: clock.from_milliseconds(int.max(s.started, s.ended)),
      attributes: s.attributes,
      error: s.error,
    )
  })
}

/// Standard OTLP, usable by Jaeger, a collector, or Langfuse.
pub fn payload(session: Session, store: Store, sha256: Sha256) -> Json {
  trace.encode("eyg", "glasshouse", [], otel_spans(session, store, sha256))
}
