import eyg/analysis/type_/isomorphic as t
import eyg/runtime/cast
import eyg/runtime/value as v
import gleam/javascript/promise
import gleam/list
import gleam/result
import midas/browser
import midas/sdk/vimeo
import midas/task
import snag

pub const l = "Vimeo.MyVideos"

pub const lift = t.unit

pub fn reply() {
  t.result(
    t.List(
      t.record([
        #("name", t.String),
        #("duration", t.Integer),
        #("plays", t.Integer),
      ]),
    ),
    t.String,
  )
}

pub fn type_() {
  #(l, #(lift, reply()))
}

pub fn blocking(app, lift) {
  use Nil <- result.map(cast.as_unit(lift, Nil))
  promise.map(do(app), result_to_eyg)
}

pub fn impl(app, lift) {
  use p <- result.map(blocking(app, lift))
  v.Promise(p)
}

pub fn do(app) {
  let task = {
    use token <- task.do(vimeo.authenticate(app, []))
    vimeo.my_videos(token)
  }
  browser.run(task)
}

fn result_to_eyg(result) {
  case result {
    Ok(videos) -> v.ok(v.LinkedList(list.map(videos, video_to_eyg)))
    Error(reason) -> v.error(v.Str(snag.line_print(reason)))
  }
}

fn video_to_eyg(video) {
  let vimeo.Video(name: name, duration: duration, plays: plays, ..) = video
  v.Record([
    #("name", v.Str(name)),
    #("duration", v.Integer(duration)),
    #("plays", v.Integer(plays)),
  ])
}
