import eyg/analysis/type_/isomorphic as t
import eyg/runtime/value as v
import gleam/option
import midas/sdk/netlify/gen

pub fn t() {
  t.record([
    #("id", t.String),
    #("state", t.String),
    #("name", t.String),
    #("url", t.String),
  ])
}

pub fn to_eyg(site) {
  let gen.Site(id: id, state: state, name: name, url: url, ..) = site
  v.Record([
    #("id", v.Str(option.unwrap(id, ""))),
    #("state", v.Str(option.unwrap(state, ""))),
    #("name", v.Str(option.unwrap(name, ""))),
    #("url", v.Str(option.unwrap(url, ""))),
  ])
}
