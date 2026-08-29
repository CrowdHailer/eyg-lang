//// Read all the entries in a directory.
//// Excludes self `.` and parent `..`
//// 
//// The closest syscall is `getdents` but most other ecosystems use the read directory terminology
//// - Node.js `fs.readdirSync`
//// - In the browser `directoryHandle.entries()`
//// - C standard library readdir
//// 
//// This effect includes status information about the returned entries.

import eyg/analysis/type_/isomorphic as t
import eyg/interpreter/cast
import eyg/interpreter/value as v
import gleam/dict
import gleam/list

pub const label = "ReadDirectory"

pub type Entry {
  Directory
  File(size: Int)
}

pub type Output =
  Result(List(#(String, Entry)), String)

pub fn lift() {
  t.String
}

pub fn lower() {
  t.result(t.List(entry()), t.String)
}

/// A single directory entry, a name and what is at that name.
pub fn entry() {
  t.record([
    #("name", t.String),
    #(
      "type",
      t.union([
        #("Directory", t.unit),
        #("File", t.record([#("size", t.Integer)])),
      ]),
    ),
  ])
}

pub const decode = cast.as_string

pub fn encode(result: Output) {
  case result {
    Ok(entries) -> v.ok(v.LinkedList(list.map(entries, entry_encode)))
    Error(reason) -> v.error(v.String(reason))
  }
}

fn entry_encode(entry: #(String, Entry)) -> v.Value(a, b) {
  let #(name, entry) = entry
  let type_ = case entry {
    Directory -> v.Tagged("Directory", v.unit())
    File(size:) ->
      v.Tagged("File", v.Record(dict.from_list([#("size", v.Integer(size))])))
  }
  v.Record(dict.from_list([#("name", v.String(name)), #("type", type_)]))
}
