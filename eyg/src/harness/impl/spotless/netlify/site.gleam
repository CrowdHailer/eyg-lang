import eyg/analysis/type_/isomorphic as t
import eyg/runtime/value as v
import gleam/option
import midas/sdk/netlify/schema

pub fn t() {
  t.record([
    #("id", t.String),
    #("state", t.String),
    #("name", t.String),
    #("url", t.String),
  ])
}

pub fn to_eyg(site) {
  let schema.Site(id: id, state: state, name: name, url: url, ..) = site
  v.Record([
    #("id", v.String(option.unwrap(id, ""))),
    #("state", v.String(option.unwrap(state, ""))),
    #("name", v.String(option.unwrap(name, ""))),
    #("url", v.String(option.unwrap(url, ""))),
  ])
}
