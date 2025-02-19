import gleam/dict
import gleam/http
import gleam/io
import gleam/javascript/promise
import gleam/list
import gleam/option.{Some}
import gleam/uri
import midas/browser
import midas/task as t
import plinth/browser/window
import website/sync/dump
import website/sync/supabase
import website/sync/sync

pub fn get_origin() {
  let assert Ok(location) = uri.parse(window.location())
  let assert uri.Uri(scheme: Some(s), host: Some(h), port: p, ..) = location
  let assert Ok(s) = http.scheme_from_string(s)
  sync.Origin(s, h, p)
}

pub fn do_sync(tasks, message) {
  fn(d) {
    list.map(tasks, fn(t) {
      let #(ref, t) = t
      use result <- promise.map(browser.run(t))
      d(message(sync.HashSourceFetched(ref, result)))
    })
    Nil
  }
}

pub fn load_task() {
  use registrations <- t.do(supabase.get_registrations())
  let registrations =
    dict.from_list(
      list.map(registrations, fn(registration) {
        #(registration.name, registration.package_id)
      }),
    )

  use releases <- t.do(supabase.get_releases())
  let releases =
    list.group(releases, fn(release) { release.package_id })
    |> dict.map_values(fn(_, releases) {
      list.map(releases, fn(release) { #(release.version, release) })
      |> dict.from_list
    })

  use fragments <- t.do(supabase.get_fragments())

  t.done(dump.Dump(registrations, releases, fragments))
}

pub fn do_load(message) {
  fn(d) {
    {
      use result <- promise.map(browser.run(load_task()))
      d(message(sync.DumpDownLoaded(result)))
    }
    Nil
  }
}
