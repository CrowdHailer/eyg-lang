import eyg/analysis/type_/isomorphic as t
import eyg/runtime/cast
import eyg/runtime/value as v
import gleam/http
import gleam/javascript/promise
import gleam/option.{None}
import gleam/result
import harness/impl/spotless/netlify/site
import harness/impl/spotless/proxy
import midas/browser
import midas/sdk/netlify
import midas/sdk/netlify/schema
import midas/task
import snag

pub const l = "Netlify.CreateSite"

pub fn lift() {
  t.record([])
}

pub fn reply() {
  t.result(site.t(), t.String)
}

pub fn type_() {
  #(l, #(lift(), reply()))
}

pub fn blocking(app, lift) {
  Ok(promise.map(do(app), result_to_eyg))
}

// pub fn impl(app, lift) {
//   use p <- result.map(blocking(app, lift))
//   v.Promise(p)
// }

pub fn do(app) {
  let task = {
    use token <- task.do(netlify.authenticate(app))
    let site = schema.site_setup
    netlify.create_site(token, site, None)
  }
  let task = proxy.proxy(task, http.Https, "eyg.run", None, "/api/netlify")
  browser.run(task)
}

fn result_to_eyg(result) {
  case result {
    Ok(site) -> v.ok(site.to_eyg(site))
    Error(reason) -> v.error(v.String(snag.line_print(reason)))
  }
}
