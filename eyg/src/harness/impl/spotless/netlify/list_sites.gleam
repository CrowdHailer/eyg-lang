import eyg/analysis/type_/isomorphic as t
import eyg/runtime/cast
import eyg/runtime/value as v
import gleam/javascript/promise
import gleam/list
import gleam/option.{None}
import gleam/result
import harness/impl/spotless/netlify/site
import midas/browser
import midas/sdk/netlify
import midas/task
import snag

pub const l = "Netlify.ListSites"

pub const lift = t.unit

pub fn reply() {
  t.result(t.List(site.t()), t.String)
}

pub fn type_() {
  #(l, #(lift, reply()))
}

pub fn blocking(app, lift) {
  use Nil <- result.map(cast.as_unit(lift, Nil))
  promise.map(do(app), result_to_eyg)
}

pub fn impl(app, lift) {
  use p <- result.map(blocking(app, lift))
  v.Promise(p)
}

pub fn do(app) {
  let task = {
    use token <- task.do(netlify.authenticate(app))
    netlify.list_sites(token, None, None, None, None)
  }
  browser.run(task)
}

fn result_to_eyg(result) {
  case result {
    Ok(videos) -> v.ok(v.LinkedList(list.map(videos, site.to_eyg)))
    Error(reason) -> v.error(v.Str(snag.line_print(reason)))
  }
}
