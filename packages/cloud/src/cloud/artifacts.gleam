//// Versioned HTML bundles created by channels, served over HTTP.
////
//// Bundle rules are shared with browser-local artifacts. An artifact belongs to the channel that created it,
//// only that channel can save new versions unless the owner shares it,
//// after which any channel in the workspace can save new versions.
//// Every version is kept and served at a URL.

import artifact_bundle as artifact
import artifact_bundle/schema
import gleam/dict.{type Dict}
import gleam/erlang/process.{type Subject}
import gleam/int
import gleam/list
import gleam/option.{type Option}
import gleam/otp/actor
import gleam/result
import gleam/string
import gleam/uri

pub type File {
  File(path: String, media_type: String, content: BitArray)
}

pub type Bundle =
  List(File)

/// The channel saving or sharing an artifact, `key` is `platform:channel`.
pub type Channel {
  Channel(key: String, name: String)
}

pub type Artifact {
  Artifact(owner: Channel, shared: Bool, versions: List(Bundle))
}

pub type Saved {
  Saved(version: Int, url: String)
}

pub type Message {
  Save(
    name: String,
    bundle: Bundle,
    by: Channel,
    reply: Subject(Result(Saved, String)),
  )
  Share(name: String, by: Channel, reply: Subject(Result(String, String)))
  /// A version of an artifact, the latest without a version.
  Get(
    name: String,
    version: Option(Int),
    reply: Subject(Result(#(Int, Bundle), String)),
  )
  List(reply: Subject(List(#(String, Artifact))))
}

type State {
  State(origin: String, artifacts: Dict(String, Artifact))
}

/// Start a store, artifact URLs are under `origin`.
pub fn start(origin: String) -> Result(Subject(Message), String) {
  actor.new(State(origin:, artifacts: dict.new()))
  |> actor.on_message(handle)
  |> actor.start
  |> result.map(fn(started) { started.data })
  |> result.map_error(string.inspect)
}

fn handle(state: State, message: Message) -> actor.Next(State, Message) {
  case message {
    Save(name:, bundle:, by:, reply:) ->
      case save(state, name, bundle, by) {
        Ok(#(state, version)) -> {
          process.send(reply, Ok(Saved(version, url(state.origin, name))))
          actor.continue(state)
        }
        Error(reason) -> {
          process.send(reply, Error(reason))
          actor.continue(state)
        }
      }
    Share(name:, by:, reply:) ->
      case dict.get(state.artifacts, name) {
        Error(Nil) -> {
          process.send(reply, Error("Unknown artifact: " <> name))
          actor.continue(state)
        }
        Ok(artifact) if artifact.owner.key != by.key -> {
          process.send(reply, Error(owned(name, artifact)))
          actor.continue(state)
        }
        Ok(artifact) -> {
          process.send(reply, Ok(url(state.origin, name)))
          let artifact = Artifact(..artifact, shared: True)
          actor.continue(
            State(
              ..state,
              artifacts: dict.insert(state.artifacts, name, artifact),
            ),
          )
        }
      }
    Get(name:, version:, reply:) -> {
      process.send(reply, get(state, name, version))
      actor.continue(state)
    }
    List(reply:) -> {
      process.send(reply, dict.to_list(state.artifacts))
      actor.continue(state)
    }
  }
}

fn save(state: State, name, bundle, by: Channel) {
  use Nil <- result.try(validate(name, bundle))
  case dict.get(state.artifacts, name) {
    Ok(artifact) if artifact.owner.key != by.key && !artifact.shared ->
      Error(owned(name, artifact))
    Ok(artifact) -> {
      let artifact =
        Artifact(..artifact, versions: [bundle, ..artifact.versions])
      Ok(#(
        State(..state, artifacts: dict.insert(state.artifacts, name, artifact)),
        list.length(artifact.versions),
      ))
    }
    Error(Nil) -> {
      let artifact = Artifact(owner: by, shared: False, versions: [bundle])
      Ok(#(
        State(..state, artifacts: dict.insert(state.artifacts, name, artifact)),
        1,
      ))
    }
  }
}

fn owned(name, artifact: Artifact) {
  "Artifact "
  <> name
  <> " belongs to #"
  <> artifact.owner.name
  <> ", only that channel can change it unless it is shared"
}

fn get(state: State, name, version) {
  use artifact <- result.try(
    dict.get(state.artifacts, name)
    |> result.replace_error("Unknown artifact: " <> name),
  )
  let count = list.length(artifact.versions)
  let version = option.unwrap(version, count)
  case version > 0 && version <= count {
    True ->
      list.drop(artifact.versions, count - version)
      |> list.first
      |> result.map(fn(bundle) { #(version, bundle) })
      |> result.replace_error("Unknown version")
    False ->
      Error("Unknown version " <> int.to_string(version) <> " of " <> name)
  }
}

pub fn url(origin: String, name: String) -> String {
  origin <> "/artifacts/" <> uri.percent_encode(name) <> "/"
}

/// Bundles need a UTF-8 `index.html`, unique relative paths and explicit media types,
/// with at most 128 files and 2 MiB.
pub fn validate(name: String, files: Bundle) -> Result(Nil, String) {
  list.map(files, fn(file) {
    schema.ArtifactFile(file.path, file.media_type, file.content)
  })
  |> artifact.validate(name, _)
}

pub fn call(store: Subject(Message), make) {
  process.call(store, 5000, make)
}

/// The file at `path` in a bundle, `index.html` for an empty path.
pub fn file(bundle: Bundle, path: String) -> Result(File, Nil) {
  let path = case path {
    "" -> "index.html"
    path -> path
  }
  list.find(bundle, fn(file) { file.path == path })
}
