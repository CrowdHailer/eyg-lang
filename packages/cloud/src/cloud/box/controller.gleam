import cloud/apex/context.{type Context}
import cloud/beam/execute
import cloud/box
import cloud/data/boxes
import cloud/file_system
import gleam/bytes_tree
import gleam/dict
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

/// A box without a name is transient, it can only be reached by its id.
pub fn create(request, context: Context) {
  use body <- wisp.require_json(request)
  let decoder = {
    use name <- decode.optional_field(
      "name",
      None,
      decode.map(decode.string, Some),
    )
    use from <- decode.optional_field(
      "from",
      None,
      decode.map(decode.string, Some),
    )
    decode.success(#(name, from))
  }
  case decode.run(body, decoder) {
    Error(_) -> reason(400, "Expected an optional name and box to start from")
    Ok(#(name, from)) -> {
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

/// The named boxes, transient boxes are not listed.
pub fn list(context: Context) {
  use boxes <- try(box.named(context))
  wisp.json_response(json.to_string(json.array(boxes, encode)), 200)
}

pub fn get(id, context: Context) {
  use box <- try(box.latest(context, id))
  wisp.json_response(json.to_string(encode(box)), 200)
}

/// The names of the box's secrets, their values are never returned.
pub fn secrets(id, context: Context) {
  use _ <- try(box.latest(context, id))
  use secrets <- try(box.secrets(context, id))
  dict.keys(secrets)
  |> list.sort(string.compare)
  |> json.array(json.string)
  |> json.to_string
  |> wisp.json_response(200)
}

/// The request body is the value of the secret.
pub fn set_secret(request, id, name, context: Context) {
  use value <- wisp.require_string_body(request)
  use Nil <- try(box.set_secret(context, id, name, value))
  wisp.no_content()
}

pub fn delete_secret(id, name, context: Context) {
  use Nil <- try(box.delete_secret(context, id, name))
  wisp.no_content()
}

/// A directory is listed, a file is returned as it was written.
pub fn read(id, path, context: Context) {
  use box <- try(box.latest(context, id))
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
pub fn write(request, id, path, context: Context) {
  use contents <- wisp.require_bit_array_body(request)
  use root <- change(id, context)
  use root <- mfs.then(file_system.make_directory(root, path <> "/.."))
  use root <- mfs.try(root)
  file_system.write(root, path, contents)
}

pub fn delete(id, path, context: Context) {
  use root <- change(id, context)
  file_system.delete(root, path)
}

fn change(id, context, operation) {
  use box <- try(box.change(context, id, operation))
  wisp.json_response(json.to_string(encode(box)), 200)
}

fn encode(box: boxes.Box) {
  json.object([
    #("id", json.string(box.id)),
    #("name", json.nullable(box.name, json.string)),
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
