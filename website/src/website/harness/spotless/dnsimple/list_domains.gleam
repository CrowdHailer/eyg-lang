import eyg/analysis/type_/isomorphic as t
import eyg/interpreter/cast
import eyg/interpreter/value as v
import gleam/dict
import gleam/http
import gleam/javascript/promise
import gleam/list
import gleam/option.{None, Some}
import gleam/result
import midas/browser
import midas/sdk/dnsimple
import midas/sdk/dnsimple/schema
import midas/task
import snag
import website/harness/spotless/dnsimple/auth
import website/harness/spotless/proxy

pub const l = "DNSimple.ListDomains"

pub fn lift() {
  t.unit
}

pub fn reply() {
  t.result(t.List(t.record([#("id", t.String), #("name", t.String)])), t.String)
}

pub fn type_() {
  #(l, #(lift(), reply()))
}

pub fn blocking(app, lift) {
  use Nil <- result.try(cast.as_unit(lift, Nil))
  Ok(promise.map(do(app), result_to_eyg))
}

pub fn impl(app, lift) {
  use p <- result.map(blocking(app, lift))
  v.Promise(p)
}

pub fn do(local) {
  let task = {
    use #(token, account_id) <- task.do(auth.authenticate(local))
    // dnsimple.list_domains(token, account_id, None, None, None)
    todo as "need dynamic in opanispec"
  }
  let task = proxy.proxy(task, http.Https, "eyg.run", None, "/api/dnsimple")
  browser.run(task)
}

fn result_to_eyg(result) {
  case result {
    Ok(domains) -> v.ok(v.LinkedList(list.map(domains, domain_to_eyg)))
    Error(reason) -> v.error(v.String(snag.line_print(reason)))
  }
}

fn domain_to_eyg(message) {
  let schema.Domain(id: id, name: name, ..) = message
  let assert Some(id) = id
  let assert Some(name) = name

  v.Record(dict.from_list([#("id", v.Integer(id)), #("name", v.String(name))]))
}
