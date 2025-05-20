import eyg/analysis/type_/isomorphic as t
import eyg/interpreter/cast
import eyg/interpreter/value as v
import gleam/http
import gleam/javascript/promise
import gleam/option.{None}
import gleam/result
import midas/browser
import midas/task
import netlify
import snag
import website/harness/spotless/proxy

pub const l = "Netlify.DeploySite"

pub fn lift() {
  t.record([#("site", t.String), #("files", t.List(t.file))])
}

pub fn reply() {
  t.result(t.unit, t.String)
}

pub fn type_() {
  #(l, #(lift(), reply()))
}

pub fn blocking(app, lift) {
  use site_id <- result.try(cast.field("site", cast.as_string, lift))
  use files <- result.try(cast.field(
    "files",
    cast.as_list_of(_, fn(f) {
      case cast.field("name", cast.as_string, f) {
        Ok(name) ->
          case cast.field("content", cast.as_binary, f) {
            Ok(content) -> Ok(#(name, content))
            Error(reason) -> Error(reason)
          }
        Error(reason) -> Error(reason)
      }
    }),
    lift,
  ))
  Ok(promise.map(do(app, site_id, files), result_to_eyg))
}

// fn impl(app, lift) {
//   use p <- result.map(blocking(app, lift))
//   v.Promise(p)
// }

pub fn do(app, site_id, files) {
  let task = {
    use token <- task.do(netlify.authenticate(app))
    netlify.deploy_site(token, site_id, files)
  }
  let task = proxy.proxy(task, http.Https, "eyg.run", None, "/api/netlify")
  browser.run(task)
}

fn result_to_eyg(result) {
  case result {
    Ok(status) -> v.ok(v.String(status))
    Error(reason) -> v.error(v.String(snag.line_print(reason)))
  }
}
