import eyg/analysis/type_/isomorphic as t
import eyg/runtime/cast
import eyg/runtime/value as v
import gleam/javascript/promise
import gleam/list
import gleam/result
import midas/browserx
import midas/sdk/netlify
import midas/task
import snag

pub const l = "Netlify.ListSites"

pub const lift = t.unit

pub fn reply() {
  t.result(
    t.List(
      t.record([
        #("id", t.String),
        #("state", t.String),
        #("name", t.String),
        #("url", t.String),
      ]),
    ),
    t.String,
  )
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
    netlify.list_sites(token)
  }
  browserx.run(task)
}

fn result_to_eyg(result) {
  case result {
    Ok(videos) -> v.ok(v.LinkedList(list.map(videos, site_to_eyg)))
    Error(reason) -> v.error(v.Str(snag.line_print(reason)))
  }
}

fn site_to_eyg(site) {
  let netlify.Site(id: id, state: state, name: name, url: url) = site
  v.Record([
    #("id", v.Str(id)),
    #("state", v.Str(state)),
    #("name", v.Str(name)),
    #("url", v.Str(url)),
  ])
}
