import eyg/analysis/type_/isomorphic as t
import eyg/interpreter/cast
import eyg/interpreter/value as v
import gleam/dict
import gleam/http as gleam_http
import gleam/javascript/promise
import gleam/option.{None, Some}
import gleam/result.{try}
import gleam/uri.{Uri}
import midas/browser
import website/harness/http

pub const l = "Follow"

pub fn lift() {
  url()
}

pub fn lower() {
  t.result(url(), t.String)
}

fn url() {
  t.record([
    #("scheme", http.scheme()),
    // host + port = authority
    #("host", t.String),
    #("port", t.option(t.String)),
    // path can be empty
    #("path", t.String),
    #("query", t.option(t.String)),
  ])
}

fn url_to_gleam(url) {
  use scheme <- try(cast.field("scheme", http.scheme_to_gleam, url))
  use host <- try(cast.field("host", cast.as_string, url))
  use port <- try(cast.field("port", cast.as_option(_, cast.as_integer), url))
  use path <- try(cast.field("path", cast.as_string, url))
  use query <- try(cast.field("query", cast.as_option(_, cast.as_string), url))
  Ok(Uri(
    scheme: Some(gleam_http.scheme_to_string(scheme)),
    userinfo: None,
    host: Some(host),
    port:,
    path:,
    query:,
    fragment: None,
  ))
}

fn url_to_eyg(url: uri.Uri) {
  case url {
    Uri(scheme: Some(scheme), host: Some(host), port:, path:, query:, ..) -> {
      case gleam_http.scheme_from_string(scheme) {
        Ok(scheme) -> {
          v.Record(
            dict.from_list([
              #("scheme", http.scheme_to_eyg(scheme)),
              #("host", v.String(host)),
              #("port", v.option(port, v.Integer)),
              #("path", v.String(path)),
              #("query", v.option(query, v.String)),
            ]),
          )
          |> v.ok()
        }
        Error(_) -> v.error(v.String("invalid scheme"))
      }
    }
    _ -> {
      echo url
      v.error(v.String("invalid url"))
    }
  }
}

pub fn type_() {
  #(l, #(lift(), lower()))
}

pub fn blocking(lift) {
  use url <- result.map(url_to_gleam(lift))
  promise.map(do(url), result_to_eyg)
}

pub fn preflight(lift) {
  use url <- result.try(url_to_gleam(lift))
  Ok(fn() { promise.map(do(url), result_to_eyg) })
}

fn do(url) {
  use redirected <- promise.map(browser.do_follow(url))
  uri.parse(redirected)
}

fn result_to_eyg(result) {
  case result {
    Ok(url) -> url_to_eyg(url)
    Error(Nil) -> v.error(v.String("Invalid url"))
  }
}
