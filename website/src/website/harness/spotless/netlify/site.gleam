import eyg/analysis/type_/isomorphic as t
import eyg/interpreter/value as v
import gleam/dict
import gleam/option
import netlify/schema

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
  v.Record(
    dict.from_list([
      #("id", v.String(option.unwrap(id, ""))),
      #("state", v.String(option.unwrap(state, ""))),
      #("name", v.String(option.unwrap(name, ""))),
      #("url", v.String(option.unwrap(url, ""))),
    ]),
  )
}
