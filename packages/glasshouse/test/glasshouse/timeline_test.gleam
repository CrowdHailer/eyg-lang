import eyg/interpreter/value as v
import glasshouse/diff
import glasshouse/fixtures
import glasshouse/helpers.{sha256}
import glasshouse/journal
import glasshouse/recorder
import glasshouse/timeline.{Whole}
import gleam/dict
import gleam/list
import gleam/option.{None, Some}

pub fn a_frame_for_every_effect_test() {
  let #(session, store) = fixtures.session()
  let frames = timeline.frames(session, store)
  assert list.map(frames, fn(f) { f.entry.label })
    == ["ReadFile", "ReadFile", "WriteFile", "StandardOut"]
  assert list.map(frames, fn(f) { f.index }) == [0, 1, 2, 3]
  assert list.map(frames, fn(f) { f.event }) == [0, 3, 3, 3]
  assert list.map(frames, fn(f) { f.position }) == [0, 0, 1, 2]
}

pub fn files_are_known_once_read_test() {
  let #(session, store) = fixtures.session()
  let assert [config, read, write, print] = timeline.frames(session, store)
  assert dict.get(config.files, "/project/README.md")
    == Ok(timeline.File(Whole(<<fixtures.readme:utf8>>)))
  assert dict.get(config.files, "/project/notes.txt") == Error(Nil)
  assert dict.get(read.files, "/project/notes.txt")
    == Ok(timeline.File(Whole(<<fixtures.notes_before:utf8>>)))
  assert dict.get(write.files, "/project/notes.txt")
    == Ok(timeline.File(Whole(<<fixtures.notes_after:utf8>>)))
  assert print.change == None
  assert print.files == write.files
}

pub fn earlier_frames_keep_their_state_test() {
  let #(session, store) = fixtures.session()
  let assert [_, read, _write, _] = timeline.frames(session, store)
  assert dict.get(read.files, "/project/notes.txt")
    == Ok(timeline.File(Whole(<<fixtures.notes_before:utf8>>)))
}

pub fn write_changes_have_a_diff_test() {
  let #(session, store) = fixtures.session()
  let assert [_, _, write, _] = timeline.frames(session, store)
  let assert Some(change) = write.change
  assert timeline.change_path(change) == "/project/notes.txt"
  assert timeline.is_modification(change)
  assert timeline.change_diff(change)
    == Some([
      diff.Keep("line one"),
      diff.Delete("line two"),
      diff.Insert("line 2"),
      diff.Keep("line three"),
      diff.Insert("line four"),
    ])
}

pub fn listing_includes_parent_directories_test() {
  let #(session, store) = fixtures.session()
  let assert [_, _, write, _] = timeline.frames(session, store)
  assert list.map(timeline.listing(write.files), fn(e) { e.0 })
    == ["/project/README.md", "/project/notes.txt"]
}

fn record(recorder, label, lift, reply, path) {
  recorder.record(recorder, label, lift, reply, journal.Performed, path, 0, 0)
}

fn file(path, contents) {
  v.Record(
    dict.from_list([
      #("path", v.String(path)),
      #("contents", v.Binary(<<contents:utf8>>)),
    ]),
  )
}

fn frames_of(recorder) {
  let session = fixtures.single_run(recorder.journal(recorder))
  timeline.frames(session, recorder.store(recorder))
}

pub fn append_to_unknown_file_test() {
  let frames =
    recorder.new(sha256)
    |> record("AppendFile", file("/log.txt", "entry\n"), v.ok(v.unit()), None)
    |> frames_of
  let assert [frame] = frames
  assert dict.get(frame.files, "/log.txt")
    == Ok(timeline.File(timeline.Ending(<<"entry\n">>)))
  let assert Some(change) = frame.change
  assert timeline.change_diff(change) == Some([diff.Insert("entry")])
}

pub fn delete_and_directories_test() {
  let frames =
    recorder.new(sha256)
    |> record("WriteFile", file("/a/b/c.txt", "x\n"), v.ok(v.unit()), None)
    |> record("DeleteFile", v.String("/a/b/c.txt"), v.ok(v.unit()), None)
    |> record("MakeDirectory", v.String("/d/e"), v.ok(v.unit()), None)
    |> frames_of
  let assert [written, deleted, made] = frames
  assert dict.get(written.files, "/a/b") == Ok(timeline.Directory)
  assert dict.get(deleted.files, "/a/b/c.txt") == Ok(timeline.Absent)
  let assert Some(removed) = deleted.change
  assert timeline.change_diff(removed) == Some([diff.Delete("x")])
  assert dict.get(made.files, "/d/e") == Ok(timeline.Directory)
  assert dict.get(made.files, "/d") == Ok(timeline.Directory)
}

pub fn failed_effects_change_nothing_test() {
  let frames =
    recorder.new(sha256)
    |> record(
      "WriteFile",
      file("/x.txt", "x"),
      v.error(v.String("permission denied")),
      None,
    )
    |> frames_of
  let assert [frame] = frames
  assert frame.change == None
  assert dict.size(frame.files) == 0
}

pub fn directory_listing_test() {
  let child = fn(name, type_) {
    v.Record(dict.from_list([#("name", v.String(name)), #("type", type_)]))
  }
  let frames =
    recorder.new(sha256)
    |> record(
      "ReadDirectory",
      v.String("/src"),
      v.ok(
        v.LinkedList([
          child(
            "main.eyg",
            v.Tagged(
              "File",
              v.Record(dict.from_list([#("size", v.Integer(12))])),
            ),
          ),
          child("lib", v.Tagged("Directory", v.unit())),
        ]),
      ),
      None,
    )
    |> frames_of
  let assert [frame] = frames
  assert dict.get(frame.files, "/src/main.eyg")
    == Ok(timeline.File(timeline.Unseen(Some(12))))
  assert dict.get(frame.files, "/src/lib") == Ok(timeline.Directory)
  assert frame.change == Some(timeline.Listed("/src", ["main.eyg", "lib"]))
}

pub fn clone_and_commit_test() {
  let frames =
    recorder.new(sha256)
    |> record(
      "Clone",
      v.Record(
        dict.from_list([#("url", v.String("https://example.com/r.git"))]),
      ),
      v.ok(v.Record(dict.from_list([#("commit", v.String("abc123"))]))),
      Some("/work/r"),
    )
    |> record(
      "Commit",
      v.Record(dict.from_list([#("path", v.String("/work/r"))])),
      v.ok(v.Record(dict.from_list([#("commit", v.String("def456"))]))),
      Some("/work/r"),
    )
    |> frames_of
  let assert [cloned, committed] = frames
  assert dict.get(cloned.files, "/work/r")
    == Ok(timeline.Checkout("https://example.com/r.git", "abc123"))
  assert dict.get(committed.files, "/work/r")
    == Ok(timeline.Checkout("https://example.com/r.git", "def456"))
}

pub fn empty_directories_are_listed_test() {
  let frames =
    recorder.new(sha256)
    |> record("MakeDirectory", v.String("/d/e"), v.ok(v.unit()), None)
    |> frames_of
  let assert [made] = frames
  assert list.map(timeline.listing(made.files), fn(e) { e.0 }) == ["/d/e"]
}

pub fn relative_test() {
  assert timeline.relative("/project/a.txt", "/project") == "a.txt"
  assert timeline.relative("/project/a.txt", "/project/") == "a.txt"
  assert timeline.relative("/elsewhere/a.txt", "/project") == "/elsewhere/a.txt"
}

pub fn parent_test() {
  assert timeline.parent("/a/b.txt") == "/a"
  assert timeline.parent("/a") == "/"
  assert timeline.parent("relative") == ""
}

pub fn subjects_are_one_line_test() {
  let recorder =
    recorder.new(sha256)
    |> record(
      "NeonQuery",
      v.Record(
        dict.from_list([
          #("connection", v.String("signups")),
          #("query", v.String("SELECT count(*)\nFROM signups")),
          #("params", v.LinkedList([])),
          #("at", v.none()),
        ]),
      ),
      v.ok(v.unit()),
      None,
    )
    |> record(
      "Fetch",
      v.Record(
        dict.from_list([
          #("method", v.Tagged("GET", v.unit())),
          #("host", v.String("example.com")),
          #("path", v.String("/signups")),
        ]),
      ),
      v.ok(v.unit()),
      None,
    )
    |> record(
      "ReadFile",
      file("/p/a.txt", ""),
      v.ok(v.unit()),
      Some("/p/a.txt"),
    )
    |> record(
      "Sign",
      v.Record(
        dict.from_list([
          #("key", v.String("a key with a long name to be truncated")),
          #("data", v.String("data that is also long")),
        ]),
      ),
      v.ok(v.unit()),
      None,
    )
  let store = recorder.store(recorder)
  let subjects =
    recorder.journal(recorder)
    |> list.map(timeline.subject(_, "/p", store))
  assert subjects
    == [
      "signups SELECT count(*) FROM signups",
      "GET example.com/signups",
      "a.txt",
      "{data: \"data that is also long\", key: \"a key with a long nam…",
    ]
}
