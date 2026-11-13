//// Triggers run an EYG script when an event in a channel matches a pattern.
////
//// Triggers are installed per channel, by the channel's configuration or by programs
//// with the `AddTrigger` effect. A pattern is a pure EYG function from the event to a boolean.
//// Scripts are functions of the event, or source text with `event` in scope, run with the channel shell.
//// Patterns and function scripts are kept as captured expressions, source scripts as text,
//// see `notes/cloud-process-boundaries.md`.

import cloud/plugins/chat_input
import cloud/plugins/discord_input
import cloud/plugins/slack_input
import eyg/analysis/type_/isomorphic as t
import eyg/interpreter/break
import eyg/interpreter/capture
import eyg/interpreter/cast
import eyg/interpreter/state
import eyg/interpreter/value as v
import eyg/ir/tree as ir
import eyg/parser
import gleam/list
import gleam/result

/// A pure function from event to boolean,
/// captured with only the variables it uses so it can be sent between processes.
pub type Pattern =
  ir.Node(#(Int, Int))

pub type Trigger {
  Trigger(name: String, pattern: Pattern, script: Script, active: Bool)
}

/// What a trigger runs when its pattern matches, with the channel shell.
pub type Script {
  /// A function from the event, captured like a pattern. It may perform effects.
  Function(Pattern)
  /// EYG source with `event` in scope.
  Source(String)
}

/// The type of the `event` value given to patterns and scripts, a union of every event.
/// Chat platforms retain their native tags and payloads;
/// other connections report events tagged with their source, see `guides/cloud/trigger_events.md`.
pub fn event_type() {
  let github = fn(fields) {
    t.record([
      #("connection", t.String),
      #("repository", t.String),
      #("actor", t.String),
      #("url", t.String),
      ..fields
    ])
  }
  t.union(
    list.flatten([
      chat_input.event_types(),
      slack_input.event_types(),
      discord_input.event_types(),
      [
        #(
          "GitHubIssue",
          github([
            #("action", t.String),
            #("number", t.Integer),
            #("title", t.String),
            #("body", t.String),
            #("labels", t.List(t.String)),
          ]),
        ),
        #(
          "GitHubComment",
          github([
            #("action", t.String),
            #("number", t.Integer),
            #("title", t.String),
            #("body", t.String),
          ]),
        ),
        #(
          "GitHubPullRequest",
          github([
            #("action", t.String),
            #("number", t.Integer),
            #("title", t.String),
            #("body", t.String),
            #("merged", t.boolean),
            #("branch", t.String),
            #("base", t.String),
          ]),
        ),
        #(
          "GitHubPush",
          github([
            #("branch", t.String),
            #(
              "commits",
              t.List(
                t.record([
                  #("id", t.String),
                  #("message", t.String),
                  #("author", t.String),
                ]),
              ),
            ),
          ]),
        ),
        #("GitHubStar", github([])),
        #("GitHubFork", github([#("fork", t.String)])),
        #(
          "GitHubRelease",
          github([
            #("action", t.String),
            #("tag", t.String),
            #("name", t.String),
            #("body", t.String),
          ]),
        ),
        #(
          "GitHubWorkflowRun",
          github([
            #("name", t.String),
            #("conclusion", t.String),
            #("branch", t.String),
          ]),
        ),
        #("GitHubEvent", github([#("type", t.String)])),
        #(
          "BskyPost",
          t.record([
            #("connection", t.String),
            #("uri", t.String),
            #("url", t.String),
            #("author", t.String),
            #("account", t.String),
            #("text", t.String),
            #("created_at", t.String),
            #("reply", t.boolean),
            #("likes", t.Integer),
            #("reposts", t.Integer),
            #("replies", t.Integer),
            #("source", t.String),
          ]),
        ),
        #(
          "FeedItem",
          t.record([
            #("connection", t.String),
            #("feed", t.String),
            #("id", t.String),
            #("title", t.String),
            #("link", t.String),
            #("summary", t.String),
            #("published", t.String),
          ]),
        ),
        #(
          "HackerNewsStory",
          t.record([
            #("connection", t.String),
            #("list", t.String),
            #("id", t.Integer),
            #("title", t.String),
            #("url", t.String),
            #("link", t.String),
            #("by", t.String),
            #("score", t.Integer),
            #("comments", t.Integer),
          ]),
        ),
        #(
          "LobstersStory",
          t.record([
            #("connection", t.String),
            #("list", t.String),
            #("id", t.String),
            #("title", t.String),
            #("url", t.String),
            #("link", t.String),
            #("tags", t.List(t.String)),
            #("submitter", t.String),
            #("score", t.Integer),
            #("comments", t.Integer),
          ]),
        ),
      ],
    ]),
  )
}

/// The record type of a trigger in EYG, `{name, pattern, script}`.
/// Patterns have no effects, scripts are functions of the event, or source text with `event` in scope.
pub fn type_() {
  t.record([
    #("name", t.String),
    #("pattern", t.Fun(event_type(), t.Empty, t.boolean)),
    #("script", t.Fun(event_type(), t.Var(0), t.Var(1))),
  ])
}

/// Decode a trigger, its pattern must be a function and its script must parse.
pub fn decode(
  value: state.Value(#(Int, Int)),
) -> Result(Trigger, state.Reason(#(Int, Int))) {
  use name <- result.try(cast.field("name", cast.as_string, value))
  use pattern <- result.try(cast.field("pattern", as_function, value))
  use script <- result.try(cast.field("script", as_script, value))
  Ok(Trigger(name:, pattern:, script:, active: True))
}

/// A function, or source text that parses.
fn as_script(value) {
  case value {
    v.String(code) ->
      case parser.all_from_string(code) {
        Ok(_) -> Ok(Source(code))
        Error(_) -> Error(break.IncorrectTerm("a script that parses", value))
      }
    _ ->
      as_function(value)
      |> result.map(Function)
      |> result.replace_error(break.IncorrectTerm(
        "a function or source text",
        value,
      ))
  }
}

fn as_function(value) {
  case value {
    v.Closure(..) | v.Partial(..) -> Ok(capture.capture(value, #(0, 0)))
    _ -> Error(break.IncorrectTerm("a function", value))
  }
}

pub fn describe(trigger: Trigger) -> String {
  case trigger.active {
    True -> trigger.name
    False -> trigger.name <> " (stopped)"
  }
}
