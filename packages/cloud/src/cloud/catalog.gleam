//// Account-owned box registry. Box names never become arbitrary host paths.

import cloud/beam/execute
import cloud/beam/file_system
import cloud/box
import cloud/box/store
import cloud/box/transaction as tx
import gleam/dict.{type Dict}
import gleam/erlang/process.{type Subject}
import gleam/list
import gleam/otp/actor
import gleam/result
import gleam/string
import multiformats/cid/v1
import simplifile

pub type Message {
  Names(reply: Subject(List(String)))
  Get(name: String, reply: Subject(Result(Subject(box.Message), String)))
  Create(
    name: String,
    changes: List(tx.Change),
    reply: Subject(Result(Subject(box.Message), String)),
  )
  Fork(
    name: String,
    source: String,
    root: v1.Cid,
    reply: Subject(Result(Subject(box.Message), String)),
  )
}

type State {
  State(
    directory: String,
    runtime: execute.State,
    boxes: Dict(String, Subject(box.Message)),
  )
}

pub fn valid_name(name: String) {
  name != ""
  && string.length(name) <= 63
  && list.all(string.to_graphemes(name), fn(c) {
    string.contains("abcdefghijklmnopqrstuvwxyz0123456789-", c)
  })
}

pub fn start(directory: String, runtime: execute.State) {
  actor.new_with_initialiser(30_000, fn(subject) {
    use _ <- result.try(
      simplifile.create_directory_all(directory)
      |> result.map_error(simplifile.describe_error),
    )
    use names <- result.try(
      simplifile.read_directory(directory)
      |> result.map_error(simplifile.describe_error),
    )
    use boxes <- result.try(
      list.try_fold(names, dict.new(), fn(boxes, file) {
        case string.ends_with(file, ".box.json") {
          False -> Ok(boxes)
          True -> {
            let name = string.drop_end(file, 9)
            use owner <- result.map(
              box.start(directory <> "/" <> file, box.empty(), runtime)
              |> result.map_error(string.inspect),
            )
            dict.insert(boxes, name, owner.data)
          }
        }
      }),
    )
    Ok(
      actor.initialised(State(directory, runtime, boxes))
      |> actor.returning(subject),
    )
  })
  |> actor.on_message(handle)
  |> actor.start
}

pub fn names(catalog) {
  process.call(catalog, 30_000, Names)
}

pub fn get(catalog, name) {
  process.call(catalog, 30_000, Get(name, _))
}

pub fn create(catalog, name, changes) {
  process.call(catalog, 30_000, Create(name, changes, _))
}

pub fn fork(catalog, name, source, root) {
  process.call(catalog, 30_000, Fork(name, source, root, _))
}

fn install(state: State, name, initial) {
  case valid_name(name), dict.has_key(state.boxes, name) {
    False, _ ->
      Error("Use a box name of 1–63 lowercase letters, digits or hyphens")
    _, True -> Error("Box already exists")
    True, False -> {
      use owner <- result.map(
        box.start(
          state.directory <> "/" <> name <> ".box.json",
          initial,
          state.runtime,
        )
        |> result.map_error(string.inspect),
      )
      #(
        owner.data,
        State(..state, boxes: dict.insert(state.boxes, name, owner.data)),
      )
    }
  }
}

fn handle(state: State, message: Message) {
  case message {
    Names(reply) -> {
      process.send(reply, dict.keys(state.boxes) |> list.sort(string.compare))
      actor.continue(state)
    }
    Get(name, reply) -> {
      process.send(
        reply,
        dict.get(state.boxes, name) |> result.replace_error("Unknown box"),
      )
      actor.continue(state)
    }
    Create(name, changes, reply) -> {
      let empty = box.empty()
      let initial =
        tx.prepare(empty.files, empty.files.root, changes, fn(_) { True })
        |> result.map_error(string.inspect)
        |> result.try(fn(files) {
          install(state, name, store.Snapshot(files, []))
        })
      respond(state, initial, reply)
    }
    Fork(name, source, root, reply) -> {
      let initial = {
        use source <- result.try(
          dict.get(state.boxes, source)
          |> result.replace_error("Unknown source box"),
        )
        let snapshot = box.inspect(source)
        case list.contains([snapshot.files.root, ..snapshot.history], root) {
          False -> Error("Unknown snapshot")
          True ->
            install(
              state,
              name,
              store.Snapshot(file_system.State(root, snapshot.files.blocks), []),
            )
        }
      }
      respond(state, initial, reply)
    }
  }
}

fn respond(state, outcome, reply) {
  case outcome {
    Ok(#(owner, state)) -> {
      process.send(reply, Ok(owner))
      actor.continue(state)
    }
    Error(reason) -> {
      process.send(reply, Error(reason))
      actor.continue(state)
    }
  }
}
