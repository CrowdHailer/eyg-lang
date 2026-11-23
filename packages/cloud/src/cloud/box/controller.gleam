import cloud/apex/api
import cloud/apex/context.{type Context}
import cloud/beam/execute
import cloud/box
import cloud/data/boxes
import cloud/file_system
import gleam/bytes_tree
import gleam/dynamic/decode
import gleam/http/response
import gleam/json
import gleam/list
import gleam/option.{None, Some}
import gleam/result
import gleam/string
import howdy/content
import howdy/controller
import multiformats/cid/v1
import touch_grass/file_system/read_directory
import unixfs/mfs

/// A box without a name is transient, it can only be reached by its id.
pub fn create(request: controller.Context, context: Context) {
  use body <- api.read_json(request)
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
    Ok(#(name, from)) ->
      case option.map(name, valid_name) {
        Some(False) ->
          reason(400, "A box name is lowercase letters, digits and dashes")
        _ -> {
          use box <- try(case from {
            None -> box.create(context, name)
            Some(from) -> {
              use from <- result.try(box.latest(context, from))
              box.clone(context, from, name)
            }
          })
          api.json(encode(box), 201)
        }
      }
  }
}

fn valid_name(name) {
  let allowed = "abcdefghijklmnopqrstuvwxyz0123456789-"
  name != "" && list.all(string.to_graphemes(name), string.contains(allowed, _))
}

/// The named boxes, transient boxes are not listed.
pub fn list(context: Context) {
  use boxes <- try(box.named(context))
  api.json(json.array(boxes, encode), 200)
}

pub fn get(id, context: Context) {
  use box <- try(box.latest(context, id))
  api.json(encode(box), 200)
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
      |> api.json(200)
    _ ->
      case execute.files(file_system.read(box.root, path), context.state) {
        Ok(Ok(bytes)) ->
          response.new(200)
          |> response.set_header("content-type", "application/octet-stream")
          |> response.set_body(content.Bytes(bytes_tree.from_bit_array(bytes)))
        _ -> api.status(404)
      }
  }
}

/// Missing parent directories are created.
pub fn write(request: controller.Context, id, path, context: Context) {
  use contents <- api.read_bits(request)
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
  api.json(encode(box), 200)
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
  api.json(json.object([#("reason", json.string(reason))]), status)
}
