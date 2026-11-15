import cloud/access
import cloud/beam/file_system
import cloud/box
import cloud/box/check
import cloud/box/store
import cloud/box/transaction as tx
import cloud/catalog
import cloud/overlay
import cloud/templates
import eyg/interpreter/cast
import eyg/interpreter/simple_debug
import eyg/interpreter/value as v
import gleam/bit_array
import gleam/bytes_tree
import gleam/dict
import gleam/dynamic/decode
import gleam/erlang/process.{type Subject}
import gleam/http
import gleam/http/request
import gleam/http/response
import gleam/json
import gleam/list
import gleam/result
import gleam/string
import howdy/content
import howdy/controller
import multiformats/cid/v1
import unixfs/mfs

pub type Service {
  Service(
    catalog: Subject(catalog.Message),
    access: Subject(access.Message),
    agent: overlay.Session,
  )
}

pub fn controller(service: Service) {
  controller.new("/api")
  |> controller.post("/boxes/:name/connect", fn(ctx) {
    protected(ctx, service, "connect", "/system/connection.eyg", fn(owner) {
      respond(
        ctx,
        body_text(ctx)
          |> result.try(fn(text) {
            box.connect(
              owner,
              "/system/connection.eyg",
              access.token_id(token(ctx)),
              text,
              service.agent,
            )
          })
          |> result.map(json.string),
      )
    })
  })
  |> controller.get("/templates", fn(ctx) {
    controller.json(
      ctx,
      json.array(templates.all(), fn(template) {
        json.object([
          #("id", json.string(template.id)),
          #("title", json.string(template.title)),
          #("description", json.string(template.description)),
        ])
      }),
    )
  })
  |> controller.post("/boxes/:name/templates/:template", fn(ctx) {
    admin(ctx, service, fn() {
      let outcome = {
        use template <- result.try(
          templates.get(param(ctx, "template"))
          |> result.replace_error("Unknown template"),
        )
        use owner <- result.map(catalog.create(
          service.catalog,
          param(ctx, "name"),
          template.files,
        ))
        root_json(box.inspect(owner).files.root)
      }
      respond(ctx, outcome)
    })
  })
  |> controller.get("/boxes", fn(ctx) {
    admin(ctx, service, fn() {
      controller.json(
        ctx,
        json.array(catalog.names(service.catalog), json.string),
      )
    })
  })
  |> controller.post("/boxes/:name", fn(ctx) {
    admin(ctx, service, fn() {
      respond(
        ctx,
        catalog.create(service.catalog, param(ctx, "name"), [])
          |> result.map(fn(owner) { root_json(box.inspect(owner).files.root) }),
      )
    })
  })
  |> controller.get("/boxes/:name", fn(ctx) {
    protected(ctx, service, "inspect", "/", fn(owner) {
      let snapshot = box.inspect(owner)
      let paths =
        check.paths(snapshot.files, "")
        |> result.unwrap([])
        |> list.filter(fn(path) {
          access.authorize(
            service.access,
            token(ctx),
            param(ctx, "name"),
            "read",
            path,
          )
        })
      controller.json(
        ctx,
        json.object([
          #("root", json.string(v1.to_string(snapshot.files.root))),
          #(
            "history",
            json.array(snapshot.history, fn(root) {
              json.string(v1.to_string(root))
            }),
          ),
          #("files", json.array(paths, json.string)),
        ]),
      )
    })
  })
  |> controller.get("/boxes/:name/files/*path", fn(ctx) {
    with_path(ctx, fn(path) {
      protected(ctx, service, "read", path, fn(owner) {
        let snapshot = box.inspect(owner)
        case file_system.read(snapshot.files, path, 0, 16_777_216) {
          Error(error) -> failure(ctx, 404, error)
          Ok(bytes) ->
            response.new(200)
            |> response.set_header("etag", v1.to_string(snapshot.files.root))
            |> response.set_header("content-type", "application/octet-stream")
            |> response.set_body(
              content.Bytes(bytes_tree.from_bit_array(bytes)),
            )
        }
      })
    })
  })
  |> controller.put("/boxes/:name/files/*path", fn(ctx) {
    with_path(ctx, fn(path) {
      protected(ctx, service, "write", path, fn(owner) {
        let snapshot = box.inspect(owner)
        let input = {
          use base <- result.try(header_cid(ctx, "if-match"))
          use bytes <- result.try(
            controller.read_body(ctx, 16_777_216)
            |> result.replace_error("Invalid body or larger than 16 MiB"),
          )
          let change = case request.get_header(ctx.request, "x-content-cid") {
            Ok(cid) -> reference(snapshot.files, path, cid)
            Error(_) -> Ok(tx.Put(path, bytes))
          }
          use change <- result.map(change)
          #(base, [change])
        }
        transact(ctx, service, owner, input)
      })
    })
  })
  |> controller.post("/boxes/:name/transactions", fn(ctx) {
    case catalog.get(service.catalog, param(ctx, "name")) {
      Error(error) -> failure(ctx, 404, error)
      Ok(owner) -> {
        let files = box.inspect(owner).files
        let input = decode_body(ctx, batch_decoder(files))
        transact(ctx, service, owner, input)
      }
    }
  })
  |> controller.post("/boxes/:name/fork/:target", fn(ctx) {
    admin(ctx, service, fn() {
      let outcome = {
        use root <- result.try(header_cid(ctx, "if-match"))
        use owner <- result.map(catalog.fork(
          service.catalog,
          param(ctx, "target"),
          param(ctx, "name"),
          root,
        ))
        root_json(box.inspect(owner).files.root)
      }
      respond(ctx, outcome)
    })
  })
  |> controller.post("/boxes/:name/cron/:job/run", fn(ctx) {
    protected(
      ctx,
      service,
      "run",
      "/system/cron/" <> param(ctx, "job") <> ".eyg",
      fn(owner) {
        respond(
          ctx,
          box.invoke(
            owner,
            "/system/cron/" <> param(ctx, "job") <> ".eyg",
            v.unit(),
          )
            |> result.map(fn(_) {
              json.object([#("status", json.string("ok"))])
            }),
        )
      },
    )
  })
  |> controller.post("/tokens/:name", fn(ctx) {
    let outcome = {
      use code <- result.try(body_text(ctx))
      use token <- result.map(access.issue(
        service.access,
        token(ctx),
        param(ctx, "name"),
        code,
      ))
      json.object([
        #("token", json.string(token)),
        #("id", json.string(access.token_id(token))),
      ])
    }
    respond(ctx, outcome)
  })
  |> controller.delete("/tokens/:id", fn(ctx) {
    respond(
      ctx,
      access.revoke(service.access, token(ctx), param(ctx, "id"))
        |> result.map(fn(_) { json.object([]) }),
    )
  })
  |> controller.build
}

pub fn public_controller(service) {
  list.fold(
    [http.Get, http.Post, http.Put, http.Delete, http.Patch],
    controller.new("/app"),
    fn(controller, method) {
      controller.route(controller, method, "/:name/*path", fn(ctx) {
        public_request(
          ctx,
          service,
          param(ctx, "name"),
          "/" <> param(ctx, "path"),
        )
      })
    },
  )
  |> controller.build
}

pub fn public_request(ctx: controller.Context, service: Service, name, path) {
  let outcome = {
    use owner <- result.try(catalog.get(service.catalog, name))
    use body <- result.try(
      controller.read_body(ctx, 16_777_216)
      |> result.replace_error("Invalid body"),
    )
    let input =
      v.Record(
        dict.from_list([
          #("method", v.String(http.method_to_string(ctx.request.method))),
          #("path", v.String(path)),
          #("body", v.Binary(body)),
          #(
            "headers",
            v.LinkedList(
              list.map(ctx.request.headers, fn(pair) {
                v.Record(
                  dict.from_list([
                    #("name", v.String(pair.0)),
                    #("value", v.String(pair.1)),
                  ]),
                )
              }),
            ),
          ),
        ]),
      )
    use value <- result.try(box.invoke(owner, "/system/http.eyg", input))
    let decoded = {
      use status <- result.try(cast.field("status", cast.as_integer, value))
      use body <- result.try(cast.field("body", cast.as_binary, value))
      use headers <- result.map(cast.field(
        "headers",
        cast.as_list_of(_, fn(header) {
          use name <- result.try(cast.field("name", cast.as_string, header))
          use value <- result.map(cast.field("value", cast.as_string, header))
          #(name, value)
        }),
        value,
      ))
      #(status, body, headers)
    }
    result.map_error(decoded, simple_debug.describe)
  }
  case outcome {
    Error(error) -> failure(ctx, 422, error)
    Ok(#(status, body, headers)) ->
      list.fold(
        headers,
        response.new(status)
          |> response.set_body(content.Bytes(bytes_tree.from_bit_array(body))),
        fn(response, header) {
          response.set_header(response, header.0, header.1)
        },
      )
  }
}

pub fn param(ctx, name) {
  controller.param(ctx, name) |> result.unwrap("")
}

pub fn token(ctx: controller.Context) {
  request.get_header(ctx.request, "authorization")
  |> result.unwrap("")
  |> string.replace("Bearer ", "")
}

fn admin(ctx, service: Service, then) {
  case access.authorize(service.access, token(ctx), "", "admin", "/") {
    True -> then()
    False -> failure(ctx, 403, "Administrator token required")
  }
}

fn protected(ctx, service: Service, operation, path, then) {
  case
    access.authorize(
      service.access,
      token(ctx),
      param(ctx, "name"),
      operation,
      path,
    )
  {
    False -> failure(ctx, 403, "Denied")
    True ->
      case catalog.get(service.catalog, param(ctx, "name")) {
        Ok(owner) -> then(owner)
        Error(reason) -> failure(ctx, 404, reason)
      }
  }
}

fn with_path(ctx, then) {
  case file_system.resolve_path("/" <> param(ctx, "path")) {
    Ok(path) -> then(path)
    Error(error) -> failure(ctx, 400, error)
  }
}

fn body_text(ctx) {
  controller.read_body(ctx, 16_777_216)
  |> result.replace_error("Invalid body")
  |> result.try(fn(bytes) {
    bit_array.to_string(bytes) |> result.replace_error("Expected UTF-8")
  })
}

fn decode_body(ctx, decoder) {
  body_text(ctx)
  |> result.try(fn(text) {
    json.parse(text, decoder) |> result.replace_error("Invalid JSON request")
  })
}

fn header_cid(ctx: controller.Context, name) {
  use text <- result.try(
    request.get_header(ctx.request, name)
    |> result.replace_error("Missing " <> name),
  )
  parse_cid(text)
}

fn parse_cid(text) {
  case v1.from_string(text) {
    Ok(#(cid, <<>>)) -> Ok(cid)
    _ -> Error("Invalid CID")
  }
}

fn root_json(root) {
  json.object([#("root", json.string(v1.to_string(root)))])
}

pub fn failure(ctx, status, reason) {
  controller.json(ctx, json.object([#("error", json.string(reason))]))
  |> controller.with_status(status)
}

fn respond(ctx, outcome) {
  case outcome {
    Ok(value) -> controller.json(ctx, value)
    Error(reason) -> failure(ctx, 422, reason)
  }
}

fn transact(ctx, service: Service, owner, input) {
  case input {
    Error(error) -> failure(ctx, 400, error)
    Ok(#(base, changes)) -> {
      let authorize = fn(change) {
        let operation = case change {
          tx.Put(..) -> "write"
          tx.Delete(_) -> "delete"
          tx.MakeDirectory(_) -> "mkdir"
        }
        access.authorize(
          service.access,
          token(ctx),
          param(ctx, "name"),
          operation,
          tx.path(change),
        )
      }
      case box.commit(owner, base, changes, authorize) {
        Ok(root) -> controller.json(ctx, root_json(root))
        Error(tx.Conflict(root)) ->
          controller.json(
            ctx,
            json.object([
              #("error", json.string("conflict")),
              #("root", json.string(v1.to_string(root))),
            ]),
          )
          |> controller.with_status(409)
        Error(tx.Denied(path)) -> failure(ctx, 403, "Denied: " <> path)
        Error(tx.Invalid(reason)) -> failure(ctx, 422, reason)
      }
    }
  }
}

fn reference(files: file_system.State, path, text) {
  use cid <- result.try(parse_cid(text))
  case dict.get(files.blocks, cid) {
    Ok(mfs.File(bytes)) -> Ok(tx.Put(path, bytes))
    _ -> Error("Unknown file content reference")
  }
}

fn batch_decoder(files) {
  use base <- decode.field("base", store.cid_decoder())
  use changes <- decode.field(
    "changes",
    decode.list({
      use path <- decode.field("path", decode.string)
      use operation <- decode.field("operation", decode.string)
      case operation {
        "mkdir" -> decode.success(tx.MakeDirectory(path))
        "delete" -> decode.success(tx.Delete(path))
        "put" ->
          decode.one_of(
            {
              use text <- decode.field("text", decode.string)
              decode.success(tx.Put(path, bit_array.from_string(text)))
            },
            [
              {
                use cid <- decode.field("reference", decode.string)
                case reference(files, path, cid) {
                  Ok(change) -> decode.success(change)
                  Error(reason) -> decode.failure(tx.Put(path, <<>>), reason)
                }
              },
              {
                use encoded <- decode.field("base64", decode.string)
                case bit_array.base64_decode(encoded) {
                  Ok(bytes) -> decode.success(tx.Put(path, bytes))
                  Error(_) -> decode.failure(tx.Put(path, <<>>), "base64")
                }
              },
            ],
          )
        _ -> decode.failure(tx.Delete(path), "put, mkdir or delete")
      }
    }),
  )
  decode.success(#(base, changes))
}
