//// A recorded execution of EYG code.
////
//// The code, the lock pinning its references and the journal of its effects
//// are everything needed to execute it again with the same result.

import eyg/ir/dag_json as ir_json
import glasshouse/journal.{type Entry}
import glasshouse/lock.{type Lock}
import glasshouse/value.{type Encoded}
import gleam/dynamic/decode
import gleam/json
import gleam/list
import gleam/option.{type Option, None}

pub type Run {
  Run(
    id: String,
    kind: Kind,
    /// The source text exactly as given.
    code: String,
    origin: Origin,
    /// The CID of the program with every reference content addressed.
    program: Option(String),
    lock: Lock,
    cwd: String,
    journal: List(Entry),
    outcome: Outcome,
    started: Int,
    ended: Int,
  )
}

pub type Kind {
  /// `eyg run`, a block with top-level effects.
  Block
  /// `eyg script`, the `script` field of the module is called with the arguments.
  Script(arguments: List(String))
  /// An overlay configuration, evaluated before a session starts.
  Config
  /// Code run by an agent's tool call, with the session context in scope.
  Tool(call_id: String)
  /// One input to the shell, evaluated in the scope left by the cells before it.
  Cell
}

/// Where the source text came from.
pub type Origin {
  File(path: String)
  Inline
  Stdin
  Repl
}

pub type Outcome {
  /// The final value of the program.
  Returned(Encoded)
  /// The program ended without a value, i.e. a block of assignments.
  Finished
  /// The program stopped the process with a status.
  Exited(status: Int)
  /// The program raised an error while running.
  Failed(reason: String)
  /// The program never ran, it did not parse or type check.
  Rejected(reason: String)
}

/// Every stored block the run refers to.
pub fn references(run: Run) -> List(String) {
  let outcome = case run.outcome {
    Returned(encoded) -> value.references(encoded)
    _ -> []
  }
  list.flatten([
    lock.references(run.lock),
    journal.references(run.journal),
    outcome,
    option.values([run.program]),
  ])
  |> list.unique
}

pub fn encode(run: Run) -> json.Json {
  let Run(
    id:,
    kind:,
    code:,
    origin:,
    program:,
    lock:,
    cwd:,
    journal:,
    outcome:,
    started:,
    ended:,
  ) = run
  json.object([
    #("id", json.string(id)),
    #("kind", kind_encode(kind)),
    #("code", json.string(code)),
    #("origin", origin_encode(origin)),
    #("program", json.nullable(program, json.string)),
    #("lock", lock.encode(lock)),
    #("cwd", json.string(cwd)),
    #("journal", json.array(journal, journal.encode)),
    #("outcome", outcome_encode(outcome)),
    #("started", json.int(started)),
    #("ended", json.int(ended)),
  ])
}

fn kind_encode(kind) {
  case kind {
    Block -> json.object([#("type", json.string("block"))])
    Script(arguments:) ->
      json.object([
        #("type", json.string("script")),
        #("arguments", json.array(arguments, json.string)),
      ])
    Config -> json.object([#("type", json.string("config"))])
    Tool(call_id:) ->
      json.object([
        #("type", json.string("tool")),
        #("call", json.string(call_id)),
      ])
    Cell -> json.object([#("type", json.string("cell"))])
  }
}

fn kind_decoder() {
  use type_ <- decode.field("type", decode.string)
  case type_ {
    "block" -> decode.success(Block)
    "script" -> {
      use arguments <- decode.field("arguments", decode.list(decode.string))
      decode.success(Script(arguments:))
    }
    "config" -> decode.success(Config)
    "tool" -> {
      use call_id <- decode.field("call", decode.string)
      decode.success(Tool(call_id:))
    }
    "cell" -> decode.success(Cell)
    _ -> decode.failure(Block, "run kind")
  }
}

fn origin_encode(origin) {
  case origin {
    File(path:) ->
      json.object([#("type", json.string("file")), #("path", json.string(path))])
    Inline -> json.object([#("type", json.string("inline"))])
    Stdin -> json.object([#("type", json.string("stdin"))])
    Repl -> json.object([#("type", json.string("repl"))])
  }
}

fn origin_decoder() {
  use type_ <- decode.field("type", decode.string)
  case type_ {
    "file" -> {
      use path <- decode.field("path", decode.string)
      decode.success(File(path:))
    }
    "inline" -> decode.success(Inline)
    "stdin" -> decode.success(Stdin)
    "repl" -> decode.success(Repl)
    _ -> decode.failure(Inline, "origin")
  }
}

fn outcome_encode(outcome) {
  case outcome {
    Returned(encoded) ->
      json.object([
        #("type", json.string("returned")),
        #("value", ir_json.to_data_model(encoded)),
      ])
    Finished -> json.object([#("type", json.string("finished"))])
    Exited(status:) ->
      json.object([
        #("type", json.string("exited")),
        #("status", json.int(status)),
      ])
    Failed(reason:) ->
      json.object([
        #("type", json.string("failed")),
        #("reason", json.string(reason)),
      ])
    Rejected(reason:) ->
      json.object([
        #("type", json.string("rejected")),
        #("reason", json.string(reason)),
      ])
  }
}

fn outcome_decoder() {
  use type_ <- decode.field("type", decode.string)
  case type_ {
    "returned" -> {
      use encoded <- decode.field("value", ir_json.decoder(Nil))
      decode.success(Returned(encoded))
    }
    "finished" -> decode.success(Finished)
    "exited" -> {
      use status <- decode.field("status", decode.int)
      decode.success(Exited(status:))
    }
    "failed" -> {
      use reason <- decode.field("reason", decode.string)
      decode.success(Failed(reason:))
    }
    "rejected" -> {
      use reason <- decode.field("reason", decode.string)
      decode.success(Rejected(reason:))
    }
    _ -> decode.failure(Finished, "outcome")
  }
}

pub fn decoder() -> decode.Decoder(Run) {
  use id <- decode.field("id", decode.string)
  use kind <- decode.field("kind", kind_decoder())
  use code <- decode.field("code", decode.string)
  use origin <- decode.field("origin", origin_decoder())
  use program <- decode.optional_field(
    "program",
    None,
    decode.optional(decode.string),
  )
  use lock <- decode.optional_field("lock", lock.empty(), lock.decoder())
  use cwd <- decode.field("cwd", decode.string)
  use journal <- decode.field("journal", decode.list(journal.decoder()))
  use outcome <- decode.field("outcome", outcome_decoder())
  use started <- decode.optional_field("started", 0, decode.int)
  use ended <- decode.optional_field("ended", 0, decode.int)
  decode.success(Run(
    id:,
    kind:,
    code:,
    origin:,
    program:,
    lock:,
    cwd:,
    journal:,
    outcome:,
    started:,
    ended:,
  ))
}

pub fn kind_to_string(kind: Kind) -> String {
  case kind {
    Block -> "run"
    Script(..) -> "script"
    Config -> "config"
    Tool(..) -> "tool call"
    Cell -> "shell input"
  }
}
