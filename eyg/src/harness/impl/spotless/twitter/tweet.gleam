import eyg/analysis/type_/isomorphic as t
import eyg/runtime/cast
import eyg/runtime/value as v
import gleam/http
import gleam/http/request.{Request}
import gleam/io
import gleam/javascript/promise
import gleam/option.{None, Some}
import gleam/result
import gleam/string
import gleam/uri
import midas/browser
import midas/sdk/twitter
import midas/task
import snag

pub const l = "Twitter.Tweet"

pub fn lift() {
  t.String
}

pub fn reply() {
  t.result(
    t.record([
      #("id", t.String),
      #("thread_id", t.String),
      #("label_ids", t.List(t.String)),
    ]),
    t.String,
  )
}

pub fn type_() {
  #(l, #(lift(), reply()))
}

pub fn blocking(client_id, redirect_uri, lift) {
  use content <- result.try(cast.as_string(lift))
  Ok(promise.map(do(client_id, redirect_uri, content), result_to_eyg))
}

// pub fn impl(app, lift) {
//   use p <- result.map(blocking(app, lift))
//   v.Promise(p)
// }

const scopes = ["tweet.read", "tweet.write", "users.read"]

fn proxy(task) {
  case task {
    task.Fetch(request, resume) -> {
      let request =
        via_proxy(request, http.Http, "localhost:8080", None, "/proxy/twitter")
      io.debug(request)
      task.Fetch(request, fn(x) { proxy(resume(x)) })
    }
    task.Abort(_) | task.Done(_) -> task
    task.Bundle(f, m, resume) -> task.Bundle(f, m, fn(x) { proxy(resume(x)) })
    task.Follow(lift, resume) -> task.Follow(lift, fn(x) { proxy(resume(x)) })
    task.List(lift, resume) -> task.List(lift, fn(x) { proxy(resume(x)) })
    task.Log(lift, resume) -> task.Log(lift, fn(x) { proxy(resume(x)) })
    task.Read(lift, resume) -> task.Read(lift, fn(x) { proxy(resume(x)) })
    task.Write(a, b, resume) -> task.Write(a, b, fn(x) { proxy(resume(x)) })
    task.Zip(lift, resume) -> task.Zip(lift, fn(x) { proxy(resume(x)) })
  }
}

fn via_proxy(original, scheme, host, port, prefix) {
  let Request(method, headers, body, _scheme, _host, _port, path, query) =
    original
  Request(method, headers, body, scheme, host, port, prefix <> path, query)
}

pub fn url_to_proxy_request(url, scheme, host, path) {
  let source = case url {
    "https://" <> source -> source
    "http://" <> source -> source
    source -> source
  }
  let uri =
    uri.Uri(
      Some(scheme),
      None,
      Some(host),
      None,
      string.append(path, source),
      None,
      None,
    )
  let assert Ok(request) = request.from_uri(uri)
  request
}

pub fn do(client_id, redirect_uri, content) {
  let task = {
    use token <- task.do(twitter.authenticate(client_id, redirect_uri, scopes))
    twitter.create_tweet(token, content)
  }
  let task = proxy(task)
  browser.run(task)
}

fn result_to_eyg(result) {
  case result {
    Ok(response) -> v.ok(response_to_eyg(response))
    Error(reason) -> v.error(v.Str(snag.line_print(reason)))
  }
}

fn response_to_eyg(response) {
  io.debug(response)
  v.unit
}
