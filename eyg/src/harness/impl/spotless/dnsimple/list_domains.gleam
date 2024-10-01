import eyg/analysis/type_/isomorphic as t
import eyg/runtime/cast
import eyg/runtime/value as v
import gleam/javascript/promise
import gleam/list
import gleam/result
import midas/browser
import midas/sdk/dnsimple
import midas/task
import snag

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

pub fn do(app) {
  let task = {
    use #(token, account_id) <- task.do(dnsimple.authenticate(app))
    dnsimple.list_domains(token, account_id)
  }
  browser.run(task)
}

fn result_to_eyg(result) {
  case result {
    Ok(domains) -> v.ok(v.LinkedList(list.map(domains, domain_to_eyg)))
    Error(reason) -> v.error(v.Str(snag.line_print(reason)))
  }
}

fn domain_to_eyg(message) {
  let dnsimple.Domain(id, name) = message
  v.Record([#("id", v.Integer(id)), #("name", v.Str(name))])
}
