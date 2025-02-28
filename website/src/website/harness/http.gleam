import eyg/analysis/type_/isomorphic as t
import eyg/interpreter/cast
import eyg/interpreter/value as v
import gleam/dict
import gleam/http
import gleam/http/request.{Request}
import gleam/http/response.{Response}
import gleam/list
import gleam/result.{try}

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

pub fn method_to_gleam(value) {
  cast.as_varient(value, [
    #("CONNECT", cast.as_unit(_, http.Connect)),
    #("DELETE", cast.as_unit(_, http.Delete)),
    #("GET", cast.as_unit(_, http.Get)),
    #("HEAD", cast.as_unit(_, http.Head)),
    #("OPTIONS", cast.as_unit(_, http.Options)),
    #("PATCH", cast.as_unit(_, http.Patch)),
    #("POST", cast.as_unit(_, http.Post)),
    #("PUT", cast.as_unit(_, http.Put)),
    #("TRACE", cast.as_unit(_, http.Trace)),
  ])
}

pub fn method_to_eyg(method) {
  case method {
    http.Get -> v.Tagged("GET", v.unit())
    http.Post -> v.Tagged("POST", v.unit())
    http.Head -> v.Tagged("HEAD", v.unit())
    http.Put -> v.Tagged("PUT", v.unit())
    http.Delete -> v.Tagged("DELETE", v.unit())
    http.Trace -> v.Tagged("TRACE", v.unit())
    http.Connect -> v.Tagged("CONNECT", v.unit())
    http.Options -> v.Tagged("OPTIONS", v.unit())
    http.Patch -> v.Tagged("PATCH", v.unit())
    http.Other(other) -> v.Tagged("OTHER", v.String(other))
  }
}

pub fn scheme() {
  t.union([#("HTTP", t.unit), #("HTTPS", t.unit)])
}

pub fn scheme_to_gleam(value) {
  cast.as_varient(value, [
    #("HTTP", cast.as_unit(_, http.Http)),
    #("HTTPS", cast.as_unit(_, http.Https)),
  ])
}

pub fn scheme_to_eyg(scheme) {
  case scheme {
    http.Http -> v.Tagged("HTTP", v.unit())
    http.Https -> v.Tagged("HTTPS", v.unit())
  }
}

pub fn headers() {
  t.List(t.record([#("key", t.String), #("value", t.String)]))
}

pub fn headers_to_gleam(value) {
  cast.as_list_of(value, fn(h) {
    use k <- result.try(cast.field("key", cast.as_string, h))
    use value <- result.try(cast.field("value", cast.as_string, h))
    Ok(#(k, value))
  })
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

pub fn request_to_gleam(request) {
  use method <- try(cast.field("method", method_to_gleam, request))
  use scheme <- try(cast.field("scheme", scheme_to_gleam, request))
  use host <- try(cast.field("host", cast.as_string, request))
  use port <- try(cast.field(
    "port",
    cast.as_option(_, cast.as_integer),
    request,
  ))
  use path <- try(cast.field("path", cast.as_string, request))
  use query <- try(cast.field(
    "query",
    cast.as_option(_, cast.as_string),
    request,
  ))

  use headers <- try(cast.field("headers", headers_to_gleam, request))
  use body <- try(cast.field("body", cast.as_binary, request))

  Ok(Request(
    method: method,
    scheme: scheme,
    host: host,
    port: port,
    path: path,
    query: query,
    headers: headers,
    body: body,
  ))
}

pub fn request_to_eyg(request) {
  let Request(
    method: method,
    scheme: scheme,
    host: host,
    port: port,
    path: path,
    query: query,
    headers: headers,
    body: body,
  ) = request
  v.Record(
    dict.from_list([
      #("method", method_to_eyg(method)),
      #("scheme", scheme_to_eyg(scheme)),
      #("host", v.String(host)),
      #("port", v.option(port, v.Integer)),
      #("path", v.String(path)),
      #("query", v.option(query, v.String)),
      #("headers", headers_to_eyg(headers)),
      #("body", v.Binary(body)),
    ]),
  )
}

pub fn headers_to_eyg(headers) {
  v.LinkedList(
    list.map(headers, fn(h) {
      let #(k, v) = h
      v.Record(dict.from_list([#("key", v.String(k)), #("value", v.String(v))]))
    }),
  )
}

pub fn response() {
  t.record([
    #("status", t.Integer),
    #("headers", headers()),
    #("body", t.Binary),
  ])
}

pub fn response_to_gleam(response) {
  use status <- try(cast.field("status", cast.as_integer, response))
  use headers <- try(cast.field("headers", headers_to_gleam, response))
  use body <- try(cast.field("body", cast.as_binary, response))
  Ok(Response(status: status, headers: headers, body: body))
}

pub fn response_to_eyg(response) {
  let Response(status, headers, body) = response
  v.Record(
    dict.from_list([
      #("status", v.Integer(status)),
      #("headers", headers_to_eyg(headers)),
      #("body", v.Binary(body)),
    ]),
  )
}
