import eyg/analysis/type_/isomorphic as t
import eyg/interpreter/cast
import eyg/interpreter/value as v
import gleam/bit_array
import gleam/dict
import gleam/dynamic
import gleam/http
import gleam/http/request
import gleam/javascript/promise
import gleam/json
import gleam/list
import gleam/option.{None}
import gleam/result
import gleam/string
import justin
import midas/browser
import midas/task
import netlify
import oas
import snag
import website/harness/spotless/proxy

fn param_to_type(name, required, spec) {
  let value = case spec {
    oas.String -> t.String
    _ -> t.unit
  }
  let value = case required {
    True -> value
    False -> t.option(value)
  }
  #(name, value)
}

fn schema_to_type(schema, schemas) {
  case schema {
    oas.Boolean -> t.boolean
    oas.Integer -> t.Integer
    // TODO other numbers
    oas.Number -> t.unit
    oas.String -> t.String
    oas.Array(element) -> {
      let element = oas.fetch_schema(element, schemas)
      t.List(schema_to_type(element, schemas))
    }
    oas.Object(properties) -> {
      let fields =
        list.map(properties |> dict.to_list, fn(property) {
          let #(key, field) = property
          let field = oas.fetch_schema(field, schemas)

          let type_ = schema_to_type(field, schemas)
          //   TODO required
          #(key, type_)
        })
      t.record(fields)
    }
    oas.AllOf(_) | oas.AnyOf(_) | oas.OneOf(_) | oas.Null ->
      panic as "don't handle all of yet"
  }
}

pub fn bundle(paths, components: oas.Components) {
  list.flat_map(paths, fn(pair) {
    let #(pattern, path_item): #(_, oas.PathItem) = pair
    list.map(path_item.operations, fn(op) {
      let #(m, op) = op
      let parameters = list.append(op.parameters, path_item.parameters)
      let parameters =
        list.map(parameters, oas.fetch_parameter(_, components.parameters))

      let assert Ok(match) = oas.gather_match(pattern, parameters, components)
      #(match, m, parameters, op)
    })
  })
}

pub fn effects_from_oas(spec, app) {
  let oas.Document(paths: paths, components: components, ..) = spec
  let paths = bundle(dict.to_list(paths), components)
  list.filter_map(paths, fn(path) {
    let #(
      match,
      method,
      parameters,
      oas.Operation(
        request_body: request_body,
        operation_id: id,
        responses: responses,
        ..,
      ),
    ) = path

    let path_fields =
      list.filter_map(match, fn(segment) {
        case segment {
          oas.FixedSegment(_) -> Error(Nil)
          oas.MatchSegment(name, type_) -> {
            Ok(param_to_type(name, True, type_))
          }
        }
      })

    let query_fields =
      oas.query_parameters(parameters)
      |> list.map(fn(p) {
        let #(name, required, spec) = p
        let spec = oas.fetch_schema(spec, components.schemas)
        param_to_type(name, required, spec)
      })
    let fields = list.append(path_fields, query_fields)

    let lower = case dict.get(responses, oas.Status(200)) {
      Ok(response) -> {
        let oas.Response(content: content, ..) =
          oas.fetch_response(response, components.responses)
        case dict.get(content, "application/json") {
          Ok(oas.MediaType(schema)) -> {
            let schema = oas.fetch_schema(schema, components.schemas)
            schema_to_type(schema, components.schemas)
          }
          Error(Nil) -> t.unit
        }
      }
      Error(Nil) -> t.unit
    }
    let eff = #(t.record(fields), lower, fn(lift) {
      let path =
        list.fold(match, "/api/v1", fn(acc, segment) {
          case segment {
            oas.FixedSegment(value) -> acc <> "/" <> value
            oas.MatchSegment(name, schema) -> {
              case schema {
                oas.String -> {
                  let assert Ok(value) = cast.field(name, cast.as_string, lift)
                  acc <> "/" <> value
                }
                _ -> todo as "build path"
              }
            }
          }
        })

      let task = {
        use token <- task.do(netlify.authenticate(app))
        let request = case method {
          http.Get ->
            request.new()
            |> request.set_host(netlify.api_host)
            |> request.prepend_header(
              "Authorization",
              string.append("Bearer ", token),
            )
            |> request.set_path(path)
            |> request.set_body(<<>>)
          _ -> todo as "not supported method"
        }
        use response <- task.do(task.fetch(request))
        let assert Ok(body) = bit_array.to_string(response.body)

        let schema = case dict.get(responses, oas.Status(200)) {
          Ok(response) -> {
            let oas.Response(content: content, ..) =
              oas.fetch_response(response, components.responses)
            case dict.get(content, "application/json") {
              Ok(oas.MediaType(schema)) -> {
                schema
              }
              Error(Nil) -> todo
            }
          }
          Error(Nil) -> todo
        }

        let schema = oas.fetch_schema(schema, components.schemas)
        use value <- task.try(
          json.decode(body, schema_decoder(_, schema, components.schemas))
          |> result.replace_error(snag.new("Bad JSON response")),
        )
        task.done(value)
      }
      let task = proxy.proxy(task, http.Https, "eyg.run", None, "/api/netlify")
      promise.map(browser.run(task), fn(res) {
        case res {
          Ok(v) -> v.ok(v)
          Error(reason) -> v.error(v.String(snag.line_print(reason)))
        }
      })
      |> Ok
    })
    let label = "Netlify." <> justin.pascal_case(id)
    Ok(#(label, eff))
  })
}

fn schema_decoder(
  raw: dynamic.Dynamic,
  schema: oas.Schema,
  schemas,
) -> Result(v.Value(_, _), List(dynamic.DecodeError)) {
  case schema {
    oas.Boolean -> {
      use b <- result.try(dynamic.bool(raw))
      case b {
        True -> v.true()
        False -> v.false()
      }
      |> Ok
    }
    oas.Integer -> result.map(dynamic.int(raw), v.Integer)
    oas.Number -> result.map(dynamic.float(raw), fn(_) { v.Integer(99) })
    oas.String -> result.map(dynamic.string(raw), v.String)
    oas.Array(element) -> {
      let element = oas.fetch_schema(element, schemas)
      use elements <- result.try(
        dynamic.list(schema_decoder(_, element, schemas))(raw),
      )
      v.LinkedList(elements)
      |> Ok
    }

    oas.Object(properties) -> {
      let properties = dict.to_list(properties)
      use fields <- result.try(
        list.try_map(properties, fn(p) {
          let #(key, field) = p
          let field = oas.fetch_schema(field, schemas)
          use value <- result.try(dynamic.optional_field(
            key,
            dynamic.optional(schema_decoder(_, field, schemas)),
          )(raw))
          let value = v.option(option.flatten(value), fn(x) { x })
          Ok(#(key, value))
        }),
      )
      Ok(v.Record(dict.from_list(fields)))
    }
    oas.AllOf(_) | oas.AnyOf(_) | oas.OneOf(_) | oas.Null ->
      panic as "don't handle Allof"
  }
}
