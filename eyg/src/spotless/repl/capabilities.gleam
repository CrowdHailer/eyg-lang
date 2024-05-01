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
import harness/ffi/core
import plinth/browser/clipboard
import plinth/browser/file
import plinth/browser/file_system
import plinth/javascript/date
import spotless/file_system as fs
import spotless/repl/capabilities/dnsimple
import spotless/repl/capabilities/google/calendar
import spotless/repl/capabilities/google/gmail
import spotless/repl/capabilities/netlify
import spotless/repl/capabilities/open
import spotless/repl/capabilities/zip

pub fn handler_type(bindings) {
  let eff = t.Empty
  let level = 0

  let #(var, bindings) = binding.mono(level, bindings)
  let eff = t.EffectExtend("Abort", #(var, t.unit), eff)
  let eff = t.EffectExtend("Alert", #(t.String, t.unit), eff)
  let eff = t.EffectExtend("Now", #(t.unit, t.String), eff)
  let eff = t.EffectExtend("Load", #(t.unit, t.result(t.ast(), t.String)), eff)
  let eff = t.EffectExtend("Delay", #(t.Integer, t.Promise(t.unit)), eff)

  let #(var, bindings) = binding.mono(level, bindings)
  let eff = t.EffectExtend("Await", #(t.Promise(var), var), eff)
  let eff = t.EffectExtend("Open", #(t.String, t.unit), eff)
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

  let site =
    t.record([
      #("id", t.String),
      #("name", t.String),
      #("state", t.String),
      #("url", t.String),
    ])
  let eff =
    t.EffectExtend("Netlify.Sites", #(t.unit, t.Promise(t.List(site))), eff)
  let deploy = t.record([#("site", t.String), #("files", t.List(t.file))])
  let eff = t.EffectExtend("Netlify.Deploy", #(deploy, t.Promise(t.unit)), eff)

  let domain = t.record([#("id", t.String), #("name", t.String)])
  let eff =
    t.EffectExtend(
      "DNSimple.Domains",
      #(t.unit, t.Promise(t.result(t.List(domain), t.String))),
      eff,
    )
  let event = t.record([#("summary", t.String), #("start", t.String)])
  let eff =
    t.EffectExtend(
      "Google.Calendar.Events",
      #(t.String, t.Promise(t.result(t.List(event), t.String))),
      eff,
    )
  let message = t.record([#("summary", t.String), #("start", t.String)])
  let eff =
    t.EffectExtend(
      "Google.Gmail.Messages",
      #(t.String, t.Promise(t.result(t.List(message), t.String))),
      eff,
    )

  let eff = t.EffectExtend("Zip", #(t.List(t.file), t.Promise(t.Binary)), eff)

  #(eff, bindings)
}

pub fn handlers() {
  dict.new()
  |> dict.insert("Alert", impl.window_alert().2)
  |> dict.insert("Await", impl.await().2)
  |> dict.insert("Now", fn(_) {
    let now = date.now()
    Ok(v.Str(date.to_iso_string(now)))
  })
  |> dict.insert("Delay", impl.wait().2)
  |> dict.insert("File_Read", fs.file_read)
  |> dict.insert("Choose", impl.choose().2)
  |> dict.insert("HTTP", impl.http().2)
  |> dict.insert("Netlify.Sites", netlify.get_sites)
  |> dict.insert("Netlify.Deploy", netlify.deploy_site)
  |> dict.insert("DNSimple.Domains", dnsimple.list_domains)
  |> dict.insert("Google.Calendar.Events", calendar.list_events)
  |> dict.insert("Google.Gmail.Messages", gmail.list_messages)
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
  |> dict.insert("Open", open.impl)
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
