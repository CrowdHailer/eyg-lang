//// Account-managed capabilities live outside every box and its snapshots.

import cloud/beam/execute
import cloud/box/check
import cloud/box/store
import eyg/analysis/inference/levels_j/contextual as infer
import eyg/analysis/type_/isomorphic as t
import eyg/interpreter/expression
import eyg/interpreter/value as v
import gleam/bit_array
import gleam/crypto
import gleam/dict.{type Dict}
import gleam/dynamic/decode
import gleam/erlang/process.{type Subject}
import gleam/json
import gleam/otp/actor
import gleam/result
import simplifile

pub type Grant {
  Grant(box: String, code: String)
}

pub type Message {
  Authorize(
    token: String,
    box: String,
    operation: String,
    path: String,
    reply: Subject(Bool),
  )
  Issue(
    token: String,
    box: String,
    code: String,
    reply: Subject(Result(String, String)),
  )
  Revoke(token: String, id: String, reply: Subject(Result(Nil, String)))
}

type State {
  State(
    path: String,
    admin: String,
    grants: Dict(String, Grant),
    runtime: execute.State,
  )
}

fn digest(token) {
  crypto.hash(crypto.Sha256, bit_array.from_string(token))
  |> bit_array.base64_url_encode(False)
}

pub fn is_admin(token, admin) {
  token != ""
  && crypto.secure_compare(
    bit_array.from_string(token),
    bit_array.from_string(admin),
  )
}

pub fn start(path: String, admin: String, runtime: execute.State) {
  actor.new_with_initialiser(30_000, fn(subject) {
    let grants = case simplifile.read(path) {
      Error(simplifile.Enoent) -> Ok(dict.new())
      Error(error) -> Error(simplifile.describe_error(error))
      Ok(text) ->
        json.parse(text, decoder())
        |> result.map(dict.from_list)
        |> result.replace_error("Invalid account grants")
    }
    use grants <- result.map(grants)
    actor.initialised(State(path, admin, grants, runtime))
    |> actor.returning(subject)
  })
  |> actor.on_message(handle)
  |> actor.start
}

pub fn authorize(access, token, box, operation, path) {
  process.call(access, 30_000, Authorize(token, box, operation, path, _))
}

pub fn issue(access, admin, box, code) {
  process.call(access, 30_000, Issue(admin, box, code, _))
}

pub fn revoke(access, admin, id) {
  process.call(access, 30_000, Revoke(admin, id, _))
}

fn save(state: State, grants: Dict(String, Grant)) {
  let bytes =
    json.array(dict.to_list(grants), fn(pair) {
      json.object([
        #("id", json.string(pair.0)),
        #("box", json.string(pair.1.box)),
        #("code", json.string(pair.1.code)),
      ])
    })
    |> json.to_string
    |> bit_array.from_string
  store.atomic_write(state.path, bytes)
}

fn decoder() {
  decode.list({
    use id <- decode.field("id", decode.string)
    use box <- decode.field("box", decode.string)
    use code <- decode.field("code", decode.string)
    decode.success(#(id, Grant(box, code)))
  })
}

fn prepare(code, runtime) {
  use source <- result.try(check.parse(code))
  let expected =
    t.Fun(
      t.record([
        #("identity", t.String),
        #("box", t.String),
        #("operation", t.String),
        #("path", t.String),
      ]),
      t.Empty,
      t.boolean,
    )
  use runtime <- result.try(check.check(
    infer.check(infer.pure() |> infer.with_expected_type(expected), source),
    runtime,
  ))
  check.prepare(source, runtime)
}

fn allowed(state: State, token, box, operation, path) {
  case is_admin(token, state.admin), operation {
    True, _ -> True
    False, "admin" -> False
    False, _ -> {
      let outcome = {
        use grant <- result.try(
          dict.get(state.grants, digest(token))
          |> result.replace_error("Unknown token"),
        )
        case grant.box == box {
          False -> Error("Wrong box")
          True -> {
            use #(policy, runtime) <- result.try(prepare(
              grant.code,
              state.runtime,
            ))
            let input =
              v.Record(
                dict.from_list([
                  #("identity", v.String(digest(token))),
                  #("box", v.String(box)),
                  #("operation", v.String(operation)),
                  #("path", v.String(path)),
                ]),
              )
            let #(outcome, _) =
              execute.pure_loop(
                expression.call(policy, [#(input, #(0, 0))]),
                runtime,
              )
            case outcome {
              Ok(v.Tagged("True", _)) -> Ok(True)
              _ -> Error("Denied")
            }
          }
        }
      }
      result.unwrap(outcome, False)
    }
  }
}

fn handle(state: State, message: Message) {
  case message {
    Authorize(token, box, operation, path, reply) -> {
      process.send(reply, allowed(state, token, box, operation, path))
      actor.continue(state)
    }
    Issue(token, box, code, reply) -> {
      let outcome = case is_admin(token, state.admin) {
        False -> Error("Administrator token required")
        True -> {
          use _ <- result.try(prepare(code, state.runtime))
          let token =
            crypto.strong_random_bytes(32) |> bit_array.base64_url_encode(False)
          let grants =
            dict.insert(state.grants, digest(token), Grant(box, code))
          use _ <- result.map(save(state, grants))
          #(token, grants)
        }
      }
      case outcome {
        Ok(#(token, grants)) -> {
          process.send(reply, Ok(token))
          actor.continue(State(..state, grants:))
        }
        Error(reason) -> {
          process.send(reply, Error(reason))
          actor.continue(state)
        }
      }
    }
    Revoke(token, id, reply) -> {
      let grants = dict.delete(state.grants, id)
      let outcome = case is_admin(token, state.admin) {
        True -> save(state, grants)
        False -> Error("Administrator token required")
      }
      process.send(reply, outcome)
      case outcome {
        Ok(_) -> actor.continue(State(..state, grants:))
        Error(_) -> actor.continue(state)
      }
    }
  }
}

pub fn token_id(token) {
  digest(token)
}
