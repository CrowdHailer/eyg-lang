import gleam/dynamic/decode
import gleam/json
import gleam/option.{type Option, None, Some}
import gleam/result
import pog

pub type Session {
  Session(id: String, box: String)
}

/// Code that was run and what came of it.
pub type Turn {
  Turn(code: String, output: List(String), outcome: Result(String, String))
}

fn decoder() -> decode.Decoder(Session) {
  use id <- decode.field(0, decode.string)
  use box <- decode.field(1, decode.string)
  decode.success(Session(id:, box:))
}

pub fn create(box: String) -> pog.Query(Session) {
  "INSERT INTO sessions (box) VALUES ($1) RETURNING id, box"
  |> pog.query()
  |> pog.parameter(pog.text(box))
  |> pog.returning(decoder())
}

pub fn get(id: String) -> pog.Query(Session) {
  "SELECT id, box FROM sessions WHERE id = $1"
  |> pog.query()
  |> pog.parameter(pog.text(id))
  |> pog.returning(decoder())
}

pub fn list(box: String) -> pog.Query(Session) {
  "SELECT id, box FROM sessions WHERE box = $1 ORDER BY created_at, id"
  |> pog.query()
  |> pog.parameter(pog.text(box))
  |> pog.returning(decoder())
}

pub fn record_turn(session: String, turn: Turn) -> pog.Query(Nil) {
  let #(value, error) = case turn.outcome {
    Ok(value) -> #(Some(value), None)
    Error(reason) -> #(None, Some(reason))
  }
  "INSERT INTO session_turns (session, code, output, value, error)
  VALUES ($1, $2, $3, $4, $5)"
  |> pog.query()
  |> pog.parameter(pog.text(session))
  |> pog.parameter(pog.text(turn.code))
  |> pog.parameter(
    pog.text(json.to_string(json.array(turn.output, json.string))),
  )
  |> pog.parameter(pog.nullable(pog.text, value))
  |> pog.parameter(pog.nullable(pog.text, error))
}

pub fn turns(session: String) -> pog.Query(Turn) {
  "SELECT code, output::TEXT, value, error
  FROM session_turns
  WHERE session = $1
  ORDER BY id"
  |> pog.query()
  |> pog.parameter(pog.text(session))
  |> pog.returning({
    use code <- decode.field(0, decode.string)
    use output <- decode.field(1, decode.string)
    use value <- decode.field(2, decode.optional(decode.string))
    use error <- decode.field(3, decode.optional(decode.string))
    let output =
      json.parse(output, decode.list(decode.string)) |> result.unwrap([])
    decode.success(Turn(code:, output:, outcome: outcome(value, error)))
  })
}

fn outcome(value: Option(String), error: Option(String)) {
  case value, error {
    Some(value), _ -> Ok(value)
    None, Some(reason) -> Error(reason)
    None, None -> Error("")
  }
}
