import eyg/runtime/cast
import eyg/runtime/value as v
import gleam/http
import gleam/http/request.{Request}
import gleam/http/response.{Response}
import gleam/list
import gleam/result.{try}

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

pub fn scheme_to_gleam(value) {
  cast.as_varient(value, [
    #("HTTP", cast.as_unit(_, http.Http)),
    #("HTTPS", cast.as_unit(_, http.Https)),
  ])
}

pub fn headers_to_gleam(value) {
  cast.as_list_of(value, fn(h) {
    use k <- result.try(cast.field("key", cast.as_string, h))
    use value <- result.try(cast.field("value", cast.as_string, h))
    Ok(#(k, value))
  })
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

pub fn headers_to_eyg(headers) {
  v.LinkedList(
    list.map(headers, fn(h) {
      let #(k, v) = h
      v.Record([#("key", v.Str(k)), #("value", v.Str(v))])
    }),
  )
}

pub fn response_to_eyg(response) {
  let Response(status, headers, body) = response
  v.Record([
    #("status", v.Integer(status)),
    #("headers", headers_to_eyg(headers)),
    #("body", v.Binary(body)),
  ])
}
