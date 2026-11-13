//// Where recorded sessions are saved and how they are named.
////
//// Archives are written to `.eyg/traces` in the working directory,
//// or the directory set by `EYG_TRACE_DIR`.

import filepath
import glasshouse/archive.{type Archive}
import glasshouse/store
import gleam/crypto
import gleam/int
import gleam/option.{None, Some}
import gleam/result
import gleam/string
import gleam/time/calendar
import gleam/time/timestamp
import loam/system
import multiformats/cid/v1

pub fn sha256(bytes: BitArray) -> BitArray {
  crypto.hash(crypto.Sha256, bytes)
}

/// The directory traces are saved to.
pub fn directory(cwd: String) -> system.Effect(String) {
  use configured <- system.map(system.env("EYG_TRACE_DIR"))
  case configured {
    Some(directory) -> directory
    None -> filepath.join(cwd, ".eyg/traces")
  }
}

/// A unique name for a session, sortable by when it started.
pub fn new_id(started: Int) -> system.Effect(String) {
  use suffix <- system.map(system.random(4_503_599_627_370_496))
  let suffix = string.pad_start(int.to_base36(suffix), 4, "0")
  stamp(started) <> "-" <> string.lowercase(suffix)
}

/// Unix milliseconds as a compact UTC timestamp, i.e. `20261013T101522`.
pub fn stamp(milliseconds: Int) -> String {
  let #(date, time) =
    timestamp.from_unix_seconds(milliseconds / 1000)
    |> timestamp.to_calendar(calendar.utc_offset)
  let pad = fn(n, width) { string.pad_start(int.to_string(n), width, "0") }
  pad(date.year, 4)
  <> pad(calendar.month_to_int(date.month), 2)
  <> pad(date.day, 2)
  <> "T"
  <> pad(time.hours, 2)
  <> pad(time.minutes, 2)
  <> pad(time.seconds, 2)
}

/// Save an archive, returning the path written.
pub fn save(
  archive: Archive,
  cwd: String,
) -> system.Effect(Result(String, String)) {
  use directory <- system.then(directory(cwd))
  use created <- system.then(system.create_directory(directory))
  use Nil <- system.try(created)
  let path = filepath.join(directory, archive.session.id <> ".json")
  use written <- system.map(system.write_file(path, archive.to_string(archive)))
  case written {
    Ok(Nil) -> Ok(path)
    Error(reason) -> Error("failed to save trace " <> path <> ": " <> reason)
  }
}

pub fn load(path: String) -> system.Effect(Result(Archive, String)) {
  use text <- system.then(system.read_file(path))
  case text {
    Ok(text) ->
      case archive.from_string(text) {
        Ok(archive) ->
          case archive.sandbox {
            None -> system.Done(Ok(archive))
            Some(_) ->
              hydrate(
                archive,
                filepath.join(filepath.directory_name(path), "blocks"),
              )
          }
        Error(reason) -> system.Done(Error(path <> ": " <> reason))
      }
    Error(reason) -> system.Done(Error(reason))
  }
}

/// Blocks are immutable and written once across agents. Session files contain
/// only metadata/root references; `eyg sandbox export` builds portable archives.
pub fn save_shared(
  archive: Archive,
  directory: String,
) -> system.Effect(Result(String, String)) {
  let blocks = filepath.join(directory, "blocks")
  use created <- system.then(system.create_directory(blocks))
  use Nil <- system.try(created)
  use written <- system.then(
    system.fold(store.to_list(archive.store), Ok(Nil), fn(acc, entry) {
      use Nil <- system.try(acc)
      let path = filepath.join(blocks, entry.0)
      use existing <- system.then(system.file_info(path))
      case existing {
        Ok(_) -> system.Done(Ok(Nil))
        Error(_) -> {
          use written <- system.map(system.write_file_bits(path, entry.1))
          result.replace_error(written, "failed to save content block")
        }
      }
    }),
  )
  use Nil <- system.try(written)
  let path = filepath.join(directory, archive.session.id <> ".json")
  let manifest = archive.Archive(..archive, store: store.new())
  use written <- system.map(system.write_file(path, archive.to_string(manifest)))
  result.map(written, fn(_) { path })
}

fn hydrate(
  archive: Archive,
  directory: String,
) -> system.Effect(Result(Archive, String)) {
  case store.corrupt(archive.store, sha256) {
    [_, ..] -> system.Done(Error("archive contains corrupt blocks"))
    [] ->
      case archive.missing(archive) {
        [] -> system.Done(Ok(archive))
        missing -> {
          use read <- system.then(
            system.traverse(missing, fn(id) {
              use #(cid, _) <- system.try(
                v1.from_string(id)
                |> result.replace_error("invalid content identifier"),
              )
              use Nil <- system.try(case v1.to_string(cid) == id {
                True -> Ok(Nil)
                False -> Error("noncanonical content identifier")
              })
              use text <- system.map(
                system.read_file(filepath.join(directory, id)),
              )
              use text <- result.map(text)
              #(id, <<text:utf8>>)
            }),
          )
          use entries <- system.try(result.all(read))
          let blocks = store.from_list(entries)
          case store.corrupt(blocks, sha256) {
            [] ->
              hydrate(
                archive.Archive(
                  ..archive,
                  store: store.merge(archive.store, blocks),
                ),
                directory,
              )
            [_, ..] -> system.Done(Error("archive contains corrupt blocks"))
          }
        }
      }
  }
}
