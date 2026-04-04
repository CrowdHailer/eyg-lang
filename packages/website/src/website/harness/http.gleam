import eyg/analysis/type_/isomorphic as t

pub fn method() {
  t.union([
    #("CONNECT", t.unit),
    #("DELETE", t.unit),
    #("GET", t.unit),
    #("HEAD", t.unit),
    #("OPTIONS", t.unit),
    #("PATCH", t.unit),
    #("POST", t.unit),
    #("PUT", t.unit),
    #("TRACE", t.unit),
  ])
}

pub fn scheme() {
  t.union([#("HTTP", t.unit), #("HTTPS", t.unit)])
}

pub fn headers() {
  t.List(t.record([#("key", t.String), #("value", t.String)]))
}

pub fn request() {
  t.record([
    #("method", method()),
    #("scheme", scheme()),
    #("host", t.String),
    #("port", t.option(t.Integer)),
    #("path", t.String),
    #("query", t.option(t.String)),
    #("headers", headers()),
    #("body", t.Binary),
  ])
}

pub fn operation() {
  t.record([
    #("method", method()),
    #("path", t.String),
    #("query", t.option(t.String)),
    #("headers", headers()),
    #("body", t.Binary),
  ])
}

pub fn response() {
  t.record([
    #("status", t.Integer),
    #("headers", headers()),
    #("body", t.Binary),
  ])
}
