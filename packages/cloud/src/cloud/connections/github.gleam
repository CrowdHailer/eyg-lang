//// GitHub connection, events of repositories.
////
//// Events arrive by polling the public events API of each repository,
//// or as webhooks signed with the connection's secret, see `guides/cloud/connections/github.md`.
//// Both are converted to the same `GitHub*` trigger events.
//// GitHub is not a chat: comments and issues never run code, they only reach triggers.

import cloud/connection
import cloud/connections/http
import cloud/connections/poller
import cloud/data
import cloud/webhook
import gleam/dynamic/decode
import gleam/int
import gleam/json
import gleam/list
import gleam/result
import gleam/string

/// A webhook delivery, `kind` and `delivery` are the `X-GitHub-Event` and `X-GitHub-Delivery` headers.
pub type Delivery {
  Delivery(
    connection: String,
    kind: String,
    delivery: String,
    signature: String,
    body: String,
  )
}

/// Poll the events of each repository, `every` 0 relies on webhooks only.
pub fn start(
  name: String,
  repositories: List(String),
  every: Int,
  emit: fn(connection.Event) -> Nil,
) -> Nil {
  case every {
    0 -> Nil
    _ ->
      list.each(repositories, fn(repository) {
        poller.start(name, every, fn(_seen) { poll(name, repository) }, emit)
      })
  }
}

fn poll(name, repository) -> Result(List(poller.Item), String) {
  let url =
    "https://api.github.com/repos/" <> repository <> "/events?per_page=30"
  use body <- result.try(http.get(url))
  from_api(name, body)
}

/// Convert a response of the events API, newest first.
pub fn from_api(
  name: String,
  body: String,
) -> Result(List(poller.Item), String) {
  let decoder = {
    use id <- decode.field("id", decode.string)
    use type_ <- decode.field("type", decode.string)
    use repository <- decode.subfield(["repo", "name"], decode.string)
    use actor <- decode.subfield(["actor", "login"], decode.string)
    use payload <- decode.field("payload", decode.dynamic)
    decode.success(#(id, type_, repository, actor, payload))
  }
  use events <- result.try(
    json.parse(body, decode.list(decoder)) |> result.map_error(string.inspect),
  )
  list.filter_map(events, fn(event) {
    let #(id, type_, repository, actor, payload) = event
    let common = Common(name, repository, actor, repository_url(repository))
    case convert(common, api_kind(type_), payload) {
      Ok(#(value, summary)) -> Ok(poller.Item(id:, value:, summary:))
      Error(_) -> Error(Nil)
    }
  })
  |> Ok
}

/// Convert a webhook delivery, `kind` is the `X-GitHub-Event` header.
pub fn from_webhook(
  name: String,
  kind: String,
  delivery: String,
  body: String,
) -> Result(connection.Event, String) {
  let decoder = {
    use repository <- decode.subfield(
      ["repository", "full_name"],
      decode.string,
    )
    use actor <- decode.subfield(["sender", "login"], decode.string)
    use payload <- decode.then(decode.dynamic)
    decode.success(#(repository, actor, payload))
  }
  use #(repository, actor, payload) <- result.try(
    json.parse(body, decoder) |> result.map_error(string.inspect),
  )
  let common = Common(name, repository, actor, repository_url(repository))
  use #(value, summary) <- result.map(convert(common, kind, payload))
  connection.Event(name, delivery, value, summary, True)
}

/// Check the `X-Hub-Signature-256` header of a webhook delivery.
pub fn verify(secret: String, body: String, signature: String) -> Bool {
  webhook.verify_sha256(secret, body, signature)
}

fn repository_url(repository) {
  "https://github.com/" <> repository
}

/// Event API types as webhook event names.
fn api_kind(type_) {
  case type_ {
    "IssuesEvent" -> "issues"
    "IssueCommentEvent" -> "issue_comment"
    "PullRequestEvent" -> "pull_request"
    "PushEvent" -> "push"
    "WatchEvent" -> "watch"
    "ForkEvent" -> "fork"
    "ReleaseEvent" -> "release"
    other -> other
  }
}

type Common {
  Common(connection: String, repository: String, actor: String, url: String)
}

fn convert(
  common: Common,
  kind: String,
  payload: decode.Dynamic,
) -> Result(#(data.Value, String), String) {
  let Common(repository:, actor:, ..) = common
  case kind {
    "issues" -> {
      let decoder = {
        use action <- text(["action"])
        use number <- integer(["issue", "number"])
        use title <- text(["issue", "title"])
        use body <- text(["issue", "body"])
        use url <- text(["issue", "html_url"])
        use labels <- decode.then(decode.optionally_at(
          ["issue", "labels"],
          [],
          decode.list(decode.at(["name"], decode.string)),
        ))
        decode.success(#(
          event(common, "GitHubIssue", url, [
            #("action", data.string(action)),
            #("number", data.int(number)),
            #("title", data.string(title)),
            #("body", data.string(body)),
            #("labels", data.strings(labels)),
          ]),
          actor <> " " <> action <> " issue #" <> int.to_string(number),
        ))
      }
      run(payload, decoder)
    }
    "issue_comment" -> {
      let decoder = {
        use action <- text(["action"])
        use number <- integer(["issue", "number"])
        use title <- text(["issue", "title"])
        use body <- text(["comment", "body"])
        use url <- text(["comment", "html_url"])
        decode.success(#(
          event(common, "GitHubComment", url, [
            #("action", data.string(action)),
            #("number", data.int(number)),
            #("title", data.string(title)),
            #("body", data.string(body)),
          ]),
          actor <> " commented on #" <> int.to_string(number),
        ))
      }
      run(payload, decoder)
    }
    "pull_request" -> {
      let decoder = {
        use action <- text(["action"])
        use number <- integer(["pull_request", "number"])
        use title <- text(["pull_request", "title"])
        use body <- text(["pull_request", "body"])
        use url <- text(["pull_request", "html_url"])
        use merged <- decode.then(decode.optionally_at(
          ["pull_request", "merged"],
          False,
          decode.one_of(decode.bool, [decode.success(False)]),
        ))
        use branch <- text(["pull_request", "head", "ref"])
        use base <- text(["pull_request", "base", "ref"])
        decode.success(#(
          event(common, "GitHubPullRequest", url, [
            #("action", data.string(action)),
            #("number", data.int(number)),
            #("title", data.string(title)),
            #("body", data.string(body)),
            #("merged", data.bool(merged)),
            #("branch", data.string(branch)),
            #("base", data.string(base)),
          ]),
          actor <> " " <> action <> " pull request #" <> int.to_string(number),
        ))
      }
      run(payload, decoder)
    }
    "push" -> {
      let commit = {
        use id <- text(["id"])
        use message <- text(["message"])
        use author <- text(["author", "name"])
        decode.success(
          data.record([
            #("id", data.string(id)),
            #("message", data.string(message)),
            #("author", data.string(author)),
          ]),
        )
      }
      let decoder = {
        use ref <- text(["ref"])
        use commits <- decode.then(decode.optionally_at(
          ["commits"],
          [],
          decode.one_of(decode.list(commit), [decode.success([])]),
        ))
        let branch = case ref {
          "refs/heads/" <> branch -> branch
          ref -> ref
        }
        decode.success(#(
          event(common, "GitHubPush", repository_url(repository), [
            #("branch", data.string(branch)),
            #("commits", data.list(commits)),
          ]),
          actor <> " pushed to " <> branch,
        ))
      }
      run(payload, decoder)
    }
    "watch" | "star" ->
      Ok(#(
        event(common, "GitHubStar", common.url, []),
        actor <> " starred " <> repository,
      ))
    "fork" -> {
      let decoder = {
        use fork <- text(["forkee", "full_name"])
        decode.success(#(
          event(common, "GitHubFork", repository_url(fork), [
            #("fork", data.string(fork)),
          ]),
          actor <> " forked " <> repository,
        ))
      }
      run(payload, decoder)
    }
    "release" -> {
      let decoder = {
        use action <- text(["action"])
        use tag <- text(["release", "tag_name"])
        use name <- text(["release", "name"])
        use body <- text(["release", "body"])
        use url <- text(["release", "html_url"])
        decode.success(#(
          event(common, "GitHubRelease", url, [
            #("action", data.string(action)),
            #("tag", data.string(tag)),
            #("name", data.string(name)),
            #("body", data.string(body)),
          ]),
          actor <> " " <> action <> " release " <> tag,
        ))
      }
      run(payload, decoder)
    }
    "workflow_run" -> {
      let decoder = {
        use name <- text(["workflow_run", "name"])
        use conclusion <- text(["workflow_run", "conclusion"])
        use branch <- text(["workflow_run", "head_branch"])
        use url <- text(["workflow_run", "html_url"])
        decode.success(#(
          event(common, "GitHubWorkflowRun", url, [
            #("name", data.string(name)),
            #("conclusion", data.string(conclusion)),
            #("branch", data.string(branch)),
          ]),
          name <> " " <> conclusion <> " on " <> branch,
        ))
      }
      run(payload, decoder)
    }
    other ->
      Ok(#(
        event(common, "GitHubEvent", common.url, [#("type", data.string(other))]),
        actor <> " " <> other,
      ))
  }
}

fn event(common: Common, tag, url, fields) {
  let Common(connection:, repository:, actor:, ..) = common
  data.tagged(
    tag,
    data.record([
      #("connection", data.string(connection)),
      #("repository", data.string(repository)),
      #("actor", data.string(actor)),
      #("url", data.string(url)),
      ..fields
    ]),
  )
}

fn run(payload, decoder) {
  decode.run(payload, decoder) |> result.map_error(string.inspect)
}

/// A string field, missing or null is empty.
fn text(path, then) {
  decode.optionally_at(
    path,
    "",
    decode.one_of(decode.string, [decode.success("")]),
  )
  |> decode.then(then)
}

fn integer(path, then) {
  decode.optionally_at(path, 0, decode.one_of(decode.int, [decode.success(0)]))
  |> decode.then(then)
}
