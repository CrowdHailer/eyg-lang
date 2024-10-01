import eyg/analysis/type_/binding
import eyg/analysis/type_/isomorphic as t
import eyg/runtime/cast
import eyg/runtime/value as v
import eygir/annotated as a
import eygir/decode
import gleam/dict
import gleam/javascript/array
import gleam/javascript/promise
import gleam/result.{try}
import gleam/string
import harness/effect as impl
import harness/fetch
import harness/ffi/core
import harness/impl/browser/file/list as fs_list
import harness/impl/browser/file/read as fs_read
import harness/impl/browser/geolocation
import harness/impl/browser/now
import harness/impl/browser/visit
import harness/impl/spotless/dnsimple
import harness/impl/spotless/dnsimple/list_domains as dnsimple_list_domains
import harness/impl/spotless/gmail/list_messages as gmail_list_messages
import harness/impl/spotless/gmail/send as gmail_send
import harness/impl/spotless/google
import harness/impl/spotless/google_calendar/list_events as gcal_list_events
import harness/impl/spotless/netlify
import harness/impl/spotless/netlify/deploy_site as netlify_deploy_site
import harness/impl/spotless/netlify/list_sites as netlify_list_sites
import harness/impl/spotless/vimeo/my_videos as vimeo_my_videos
import plinth/browser/clipboard
import plinth/browser/file
import plinth/browser/file_system
import spotless/repl/capabilities/zip

pub fn handler_type(bindings) {
  let eff = t.Empty
  let level = 0

  let #(var, bindings) = binding.mono(level, bindings)
  let #(any, bindings) = binding.mono(level, bindings)
  let eff = t.EffectExtend("Abort", #(var, any), eff)
  let eff = t.EffectExtend("Alert", #(t.String, t.unit), eff)
  let eff = t.EffectExtend(now.l, #(t.unit, t.String), eff)
  let eff = t.EffectExtend("Fetch", #(fetch.lift(), fetch.lower()), eff)

  let eff = t.EffectExtend("Load", #(t.unit, t.result(t.ast(), t.String)), eff)
  let eff = t.EffectExtend("Wait", #(t.Integer, t.Promise(t.unit)), eff)

  let #(var, bindings) = binding.mono(level, bindings)
  let eff = t.EffectExtend("Await", #(t.Promise(var), var), eff)
  let #(l, #(lift, reply)) = visit.type_()
  let eff = t.EffectExtend(l, #(lift, reply), eff)
  let eff =
    t.EffectExtend(
      "Copy",
      #(t.String, t.Promise(t.result(t.unit, t.String))),
      eff,
    )
  let eff = t.EffectExtend("Download", #(t.file, t.unit), eff)
  let eff =
    t.EffectExtend(
      "Paste",
      #(t.unit, t.Promise(t.result(t.String, t.String))),
      eff,
    )

  let eff = t.EffectExtend("Choose", #(t.unit, t.boolean), eff)

  let #(l, #(lift, reply)) = google.type_()
  let eff = t.EffectExtend(l, #(lift, reply), eff)

  let #(l, #(lift, reply)) = gmail_send.type_()
  let eff = t.EffectExtend(l, #(lift, reply), eff)

  let #(l, #(lift, reply)) = gmail_list_messages.type_()
  let eff = t.EffectExtend(l, #(lift, reply), eff)

  let #(l, #(lift, reply)) = netlify_list_sites.type_()
  let eff = t.EffectExtend(l, #(lift, reply), eff)

  let #(l, #(lift, reply)) = netlify_deploy_site.type_()
  let eff = t.EffectExtend(l, #(lift, reply), eff)

  let #(l, #(lift, reply)) = vimeo_my_videos.type_()
  let eff = t.EffectExtend(l, #(lift, reply), eff)

  let #(l, #(lift, reply)) = dnsimple_list_domains.type_()
  let eff = t.EffectExtend(l, #(lift, reply), eff)

  let eff =
    t.EffectExtend(geolocation.l, #(geolocation.lift, geolocation.lower()), eff)

  let #(l, #(lift, reply)) = gcal_list_events.type_()
  let eff = t.EffectExtend(l, #(lift, reply), eff)

  let message = t.record([#("summary", t.String), #("start", t.String)])
  let eff =
    t.EffectExtend(
      "Google.Gmail.Messages",
      #(t.String, t.Promise(t.result(t.List(message), t.String))),
      eff,
    )

  let eff = t.EffectExtend(fs_read.l, #(fs_read.lift, fs_read.lower()), eff)
  let eff = t.EffectExtend(fs_list.l, #(fs_list.lift, fs_list.lower()), eff)

  let eff = t.EffectExtend("Zip", #(t.List(t.file), t.Promise(t.Binary)), eff)

  #(eff, bindings)
}

pub fn handlers() {
  dict.new()
  |> dict.insert("Alert", impl.window_alert().2)
  |> dict.insert("Await", impl.await().2)
  |> dict.insert(now.l, now.impl)
  |> dict.insert("Wait", impl.wait().2)
  |> dict.insert(fs_read.l, fs_read.handle)
  |> dict.insert(fs_list.l, fs_list.handle)
  |> dict.insert("Choose", impl.choose().2)
  |> dict.insert(fetch.l, fetch.handle)
  |> dict.insert(netlify_list_sites.l, netlify_list_sites.impl(netlify.local, _))
  // |> dict.insert("Netlify.Deploy", netlify.deploy_site)
  |> dict.insert(dnsimple_list_domains.l, dnsimple_list_domains.impl(
    dnsimple.local,
    _,
  ))
  |> dict.insert(geolocation.l, geolocation.handle)
  |> dict.insert(gcal_list_events.l, gcal_list_events.impl(google.local, _))
  |> dict.insert(gmail_list_messages.l, gmail_list_messages.impl(
    google.local,
    _,
  ))
  |> dict.insert("Load", fn(_) {
    let p =
      promise.map(do_load(), fn(r) {
        case r {
          Ok(exp) -> v.ok(v.LinkedList(core.expression_to_language(exp)))
          Error(reason) -> v.error(v.Str(reason))
        }
      })

    Ok(v.Promise(p))
  })
  |> dict.insert(visit.l, visit.impl)
  |> dict.insert("Copy", do_copy)
  |> dict.insert("Paste", do_paste)
  |> dict.insert("Download", do_download)
  |> dict.insert("Zip", zip.do)
}

fn do_load() {
  use file_handles <- promise.try_await(file_system.show_open_file_picker())
  let assert [file_handle] = array.to_list(file_handles)
  use file <- promise.try_await(file_system.get_file(file_handle))
  use text <- promise.map(file.text(file))
  use source <- try(
    decode.from_json(text)
    |> result.map_error(fn(e) { string.inspect(e) }),
  )
  let source = a.add_annotation(source, Nil)
  Ok(source)
  // Ok(e.from_annotated(source))
}

fn do_copy(clip_text) {
  use clip_text <- try(cast.as_string(clip_text))
  Ok(
    v.Promise(
      promise.map(clipboard.write_text(clip_text), fn(result) {
        case result {
          Ok(Nil) -> v.ok(v.unit)
          Error(reason) -> v.error(v.Str(reason))
        }
      }),
    ),
  )
}

fn do_paste(_) {
  Ok(
    v.Promise(
      promise.map(clipboard.read_text(), fn(result) {
        case result {
          Ok(clip_text) -> v.ok(v.Str(clip_text))
          Error(reason) -> v.error(v.Str(reason))
        }
      }),
    ),
  )
}

// file is name and content 
fn do_download(file) {
  use name <- try(cast.field("name", cast.as_string, file))
  use content <- try(cast.field("content", cast.as_binary, file))

  let file = file.new(content, name)
  download_file(file)
  Ok(v.unit)
}

@external(javascript, "../../browser_ffi.js", "downloadFile")
fn download_file(file: file.File) -> Nil
