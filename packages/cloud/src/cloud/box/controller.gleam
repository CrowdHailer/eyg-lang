import cloud/apex/context.{type Context}
import cloud/beam/execute
import cloud/box
import cloud/data/boxes
import cloud/file_system
import gleam/bytes_tree
import gleam/dynamic/decode
import gleam/json
import gleam/list
import gleam/option.{None, Some}
import gleam/result
import gleam/string
import multiformats/cid/v1
import touch_grass/file_system/read_directory
import unixfs/mfs
import wisp

pub fn create(request, context: Context) {
  use body <- wisp.require_json(request)
  let decoder = {
    use name <- decode.field("name", decode.string)
    use from <- decode.optional_field(
      "from",
      None,
      decode.map(decode.string, Some),
    )
    decode.success(#(name, from))
  }
  case decode.run(body, decoder) {
    Ok(#(name, from)) if name != "" -> {
      let allowed = "abcdefghijklmnopqrstuvwxyz0123456789-"
      case list.all(string.to_graphemes(name), string.contains(allowed, _)) {
        False ->
          reason(400, "A box name is lowercase letters, digits and dashes")
        True -> {
          use box <- try(case from {
            None -> box.create(context, name)
            Some(from) -> {
              use from <- result.try(box.latest(context, from))
              box.clone(context, from, name)
            }
          })
          wisp.json_response(json.to_string(encode(box)), 201)
        }
      }
    }
    _ -> reason(400, "Expected a name")
  }
}

pub fn get(name, context: Context) {
  use box <- try(box.latest(context, name))
  wisp.json_response(json.to_string(encode(box)), 200)
}

/// A directory is listed, a file is returned as it was written.
pub fn read(name, path, context: Context) {
  use box <- try(box.latest(context, name))
  case
    execute.files(file_system.read_directory(box.root, path), context.state)
  {
    Ok(Ok(entries)) ->
      json.array(entries, fn(entry) {
        let #(name, metadata) = entry
        json.object([
          #("name", json.string(name)),
          ..case metadata {
            read_directory.Directory -> [#("type", json.string("directory"))]
            read_directory.File(size) -> [
              #("type", json.string("file")),
              #("size", json.int(size)),
            ]
          }
        ])
      })
      |> json.to_string
      |> wisp.json_response(200)
    _ ->
      case execute.files(file_system.read(box.root, path), context.state) {
        Ok(Ok(bytes)) ->
          wisp.response(200)
          |> wisp.set_header("content-type", "application/octet-stream")
          |> wisp.set_body(wisp.Bytes(bytes_tree.from_bit_array(bytes)))
        _ -> wisp.not_found()
      }
  }
}

/// Missing parent directories are created.
pub fn write(request, name, path, context: Context) {
  use contents <- wisp.require_bit_array_body(request)
  use root <- change(name, context)
  use root <- mfs.then(file_system.make_directory(root, path <> "/.."))
  use root <- mfs.try(root)
  file_system.write(root, path, contents)
}

pub fn delete(name, path, context: Context) {
  use root <- change(name, context)
  file_system.delete(root, path)
}

fn change(name, context, operation) {
  use box <- try(box.change(context, name, operation))
  wisp.json_response(json.to_string(encode(box)), 200)
}

fn encode(box: boxes.Box) {
  json.object([
    #("name", json.string(box.name)),
    #("sequence", json.int(box.sequence)),
    #("root", json.string(v1.to_string(box.root))),
  ])
}

pub fn try(result, next) {
  case result {
    Ok(value) -> next(value)
    Error(box.Missing) -> reason(404, "No such box")
    Error(box.Taken) -> reason(409, "The box already exists")
    Error(box.Conflict(paths)) ->
      reason(
        409,
        "Changed since the change was made\n" <> string.join(paths, "\n"),
      )
    Error(box.Invalid(errors)) -> reason(422, string.join(errors, "\n"))
    Error(box.Failed(message)) -> reason(500, message)
  }
}

pub fn reason(status, reason) {
  wisp.json_response(
    json.to_string(json.object([#("reason", json.string(reason))])),
    status,
  )
}
