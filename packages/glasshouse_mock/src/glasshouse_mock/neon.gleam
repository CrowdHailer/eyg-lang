//// A Neon mock, a small SQL database served over Neon's HTTP protocol that keeps its history for time travel.
////
//// It understands CREATE TABLE, DROP TABLE, INSERT, SELECT, UPDATE and DELETE
//// with WHERE, GROUP BY, ORDER BY, LIMIT and RETURNING clauses, enough to demonstrate an agent working with a database.
//// Values are kept as text, the form `neon-raw-text-output` returns.
//// A connection string with `options=neon_timestamp:<time>` reads the database as it was then and is read only.

import gleam/dict.{type Dict}
import gleam/dynamic/decode
import gleam/float
import gleam/http/request.{type Request}
import gleam/http/response.{type Response}
import gleam/int
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/order
import gleam/result
import gleam/string
import gleam/time/calendar
import gleam/time/timestamp
import gleam/uri

pub type Table {
  Table(columns: List(String), rows: List(List(Option(String))))
}

pub type Database =
  Dict(String, Table)

/// Every state of the database with the time in milliseconds it started, newest first.
pub type History =
  List(#(Int, Database))

pub type Output {
  Output(
    command: String,
    count: Int,
    fields: List(String),
    rows: List(List(Option(String))),
  )
}

pub fn new() -> History {
  []
}

/// The database as it was at a time.
pub fn at(history: History, time: Int) -> Database {
  list.find(history, fn(state) { state.0 <= time })
  |> result.map(fn(state) { state.1 })
  |> result.unwrap(dict.new())
}

pub fn current(history: History) -> Database {
  case history {
    [#(_, database), ..] -> database
    [] -> dict.new()
  }
}

/// Run a script of statements separated by `;`, such as a seed file.
pub fn seed(
  history: History,
  sql: String,
  now: Int,
) -> Result(History, String) {
  use tokens <- result.try(tokenize(string.to_graphemes(sql), []))
  use statements <- result.try(script(tokens, []))
  list.try_fold(statements, history, fn(history, statement) {
    use #(database, _) <- result.map(execute(
      current(history),
      statement,
      [],
      now,
    ))
    record(history, database, now)
  })
}

/// Run one statement, at a point in time when given.
pub fn query(
  history: History,
  sql: String,
  params: List(Option(String)),
  at at_time: Option(Int),
  now now: Int,
) -> Result(#(History, Output), String) {
  use tokens <- result.try(tokenize(string.to_graphemes(sql), []))
  use statement <- result.try(case script(tokens, []) {
    Ok([statement]) -> Ok(statement)
    Ok([]) -> Error("empty query")
    Ok(_) -> Error("cannot insert multiple commands into a prepared statement")
    Error(reason) -> Error(reason)
  })
  case at_time {
    Some(time) ->
      case statement {
        Select(..) -> {
          use #(_, output) <- result.map(execute(
            at(history, time),
            statement,
            params,
            now,
          ))
          #(history, output)
        }
        _ ->
          Error(
            "cannot execute "
            <> command(statement)
            <> " in a read-only transaction",
          )
      }
    None -> {
      use #(database, output) <- result.map(execute(
        current(history),
        statement,
        params,
        now,
      ))
      #(record(history, database, now), output)
    }
  }
}

fn record(history: History, database: Database, now: Int) -> History {
  case database == current(history) {
    True -> history
    False -> [#(now, database), ..history]
  }
}

/// Answer a request to `/sql`.
pub fn handle(
  history: History,
  request: Request(BitArray),
  now: Int,
) -> #(History, Response(BitArray)) {
  let body = {
    let params =
      decode.list(
        decode.optional(
          decode.one_of(decode.string, [
            decode.int |> decode.map(int.to_string),
            decode.float |> decode.map(float.to_string),
            decode.bool
              |> decode.map(fn(b) {
                case b {
                  True -> "t"
                  False -> "f"
                }
              }),
          ]),
        ),
      )
    use query <- decode.field("query", decode.string)
    use params <- decode.optional_field("params", [], params)
    decode.success(#(query, params))
  }
  let result = {
    use connection <- result.try(
      request.get_header(request, "neon-connection-string")
      |> result.replace_error("missing neon-connection-string header"),
    )
    use at_time <- result.try(point_in_time(connection))
    use #(sql, params) <- result.try(
      json.parse_bits(request.body, body)
      |> result.replace_error("invalid request body"),
    )
    query(history, sql, params, at: at_time, now:)
  }
  case result {
    Ok(#(history, output)) -> #(history, respond(200, output_json(output)))
    Error(reason) -> #(
      history,
      respond(
        400,
        json.object([
          #("message", json.string(reason)),
          #("severity", json.string("ERROR")),
        ]),
      ),
    )
  }
}

fn respond(status, body) {
  response.new(status)
  |> response.set_header("content-type", "application/json")
  |> response.set_body(<<json.to_string(body):utf8>>)
}

fn output_json(output: Output) -> json.Json {
  let Output(command:, count:, fields:, rows:) = output
  json.object([
    #("command", json.string(command)),
    #("rowCount", json.int(count)),
    #(
      "fields",
      json.array(fields, fn(name) {
        json.object([
          #("name", json.string(name)),
          #("dataTypeID", json.int(25)),
        ])
      }),
    ),
    #(
      "rows",
      json.array(rows, fn(row) {
        json.array(row, fn(cell) { json.nullable(cell, json.string) })
      }),
    ),
    #("rowAsArray", json.bool(True)),
  ])
}

// The time a connection string travels to, from `options=neon_timestamp:<time>`.
fn point_in_time(connection: String) -> Result(Option(Int), String) {
  let options =
    uri.parse(connection)
    |> result.try(fn(connection) { option.to_result(connection.query, Nil) })
    |> result.try(uri.parse_query)
    |> result.unwrap([])
    |> list.key_find("options")
  case options {
    Ok("neon_timestamp:" <> time) ->
      case timestamp.parse_rfc3339(time) {
        Ok(time) -> {
          let #(seconds, nanoseconds) =
            timestamp.to_unix_seconds_and_nanoseconds(time)
          Ok(Some(seconds * 1000 + nanoseconds / 1_000_000))
        }
        Error(Nil) -> Error("invalid neon_timestamp " <> time)
      }
    _ -> Ok(None)
  }
}

// Tokens -----------------------------------------------------------------------

type Token {
  Word(String)
  Quoted(String)
  Text(String)
  Number(String)
  Parameter(Int)
  Symbol(String)
}

const letters = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ_"

const digits = "0123456789"

fn tokenize(
  chars: List(String),
  tokens: List(Token),
) -> Result(List(Token), String) {
  case chars {
    [] -> Ok(list.reverse(tokens))
    [" ", ..rest] | ["\n", ..rest] | ["\t", ..rest] | ["\r", ..rest] ->
      tokenize(rest, tokens)
    ["-", "-", ..rest] ->
      tokenize(list.drop_while(rest, fn(c) { c != "\n" }), tokens)
    ["'", ..rest] -> {
      use #(text, rest) <- result.try(quoted(rest, "'", ""))
      tokenize(rest, [Text(text), ..tokens])
    }
    ["\"", ..rest] -> {
      use #(name, rest) <- result.try(quoted(rest, "\"", ""))
      tokenize(rest, [Quoted(name), ..tokens])
    }
    ["$", ..rest] -> {
      let #(number, rest) = take(rest, digits, "")
      case int.parse(number) {
        Ok(index) -> tokenize(rest, [Parameter(index), ..tokens])
        Error(Nil) -> Error("syntax error at or near \"$\"")
      }
    }
    [":", ":", ..rest] -> tokenize(rest, [Symbol("::"), ..tokens])
    ["<", "=", ..rest] -> tokenize(rest, [Symbol("<="), ..tokens])
    [">", "=", ..rest] -> tokenize(rest, [Symbol(">="), ..tokens])
    ["<", ">", ..rest] | ["!", "=", ..rest] ->
      tokenize(rest, [Symbol("!="), ..tokens])
    [c, ..rest] ->
      case
        string.contains("(),*=<>;.", c),
        string.contains(digits, c),
        string.contains(letters, c)
      {
        True, _, _ -> tokenize(rest, [Symbol(c), ..tokens])
        _, True, _ -> {
          let #(number, rest) = take(chars, digits <> ".", "")
          tokenize(rest, [Number(number), ..tokens])
        }
        _, _, True -> {
          let #(word, rest) = take(chars, letters <> digits, "")
          tokenize(rest, [Word(word), ..tokens])
        }
        _, _, _ -> Error("syntax error at or near \"" <> c <> "\"")
      }
  }
}

fn take(chars, allowed, taken) {
  case chars {
    [c, ..rest] ->
      case string.contains(allowed, c) {
        True -> take(rest, allowed, taken <> c)
        False -> #(taken, chars)
      }
    [] -> #(taken, chars)
  }
}

// A quote is escaped by doubling it.
fn quoted(chars, quote, text) {
  case chars {
    [a, b, ..rest] if a == quote && b == quote ->
      quoted(rest, quote, text <> quote)
    [a, ..rest] if a == quote -> Ok(#(text, rest))
    [c, ..rest] -> quoted(rest, quote, text <> c)
    [] -> Error("unterminated quoted string")
  }
}

fn show(token) {
  case token {
    Word(word) -> word
    Quoted(name) -> "\"" <> name <> "\""
    Text(text) -> "'" <> text <> "'"
    Number(number) -> number
    Parameter(index) -> "$" <> int.to_string(index)
    Symbol(symbol) -> symbol
  }
}

// Statements -------------------------------------------------------------------

type Statement {
  Create(table: String, columns: List(String), if_not_exists: Bool)
  Drop(table: String, if_exists: Bool)
  Insert(
    table: String,
    columns: Option(List(String)),
    rows: List(List(Operand)),
    returning: Option(Projection),
  )
  Select(
    projection: Projection,
    from: Option(String),
    where: Condition,
    group: List(String),
    order: List(#(String, Bool)),
    limit: Option(Int),
  )
  Update(
    table: String,
    set: List(#(String, Operand)),
    where: Condition,
    returning: Option(Projection),
  )
  Delete(table: String, where: Condition, returning: Option(Projection))
}

type Projection {
  All
  Columns(List(#(Expression, String)))
}

type Expression {
  Operand(Operand)
  Count
}

type Operand {
  Column(String)
  Value(Option(String))
  Param(Int)
  Now
}

type Condition {
  Always
  Compare(Operand, String, Operand)
  IsNull(Operand, Bool)
  Like(Operand, Operand, Bool)
  And(Condition, Condition)
  Or(Condition, Condition)
  Not(Condition)
}

fn command(statement) {
  case statement {
    Create(..) -> "CREATE TABLE"
    Drop(..) -> "DROP TABLE"
    Insert(..) -> "INSERT"
    Select(..) -> "SELECT"
    Update(..) -> "UPDATE"
    Delete(..) -> "DELETE"
  }
}

fn script(tokens, statements) -> Result(List(Statement), String) {
  case tokens {
    [] -> Ok(list.reverse(statements))
    [Symbol(";"), ..rest] -> script(rest, statements)
    _ -> {
      use #(statement, rest) <- result.try(statement(tokens))
      case rest {
        [] | [Symbol(";"), ..] -> script(rest, [statement, ..statements])
        _ -> syntax(rest)
      }
    }
  }
}

fn syntax(tokens) -> Result(a, String) {
  case tokens {
    [] -> Error("syntax error at end of input")
    [token, ..] -> Error("syntax error at or near \"" <> show(token) <> "\"")
  }
}

fn is(token, expected) {
  case token {
    Word(word) -> string.lowercase(word) == expected
    _ -> False
  }
}

fn keyword(tokens, word, then) {
  case tokens {
    [token, ..rest] ->
      case is(token, word) {
        True -> then(rest)
        False -> syntax(tokens)
      }
    [] -> syntax(tokens)
  }
}

fn symbol(tokens, symbol, then) {
  case tokens {
    [Symbol(s), ..rest] if s == symbol -> then(rest)
    _ -> syntax(tokens)
  }
}

// Unquoted names are case insensitive.
fn name(tokens) {
  case tokens {
    [Word(word), ..rest] -> Ok(#(string.lowercase(word), rest))
    [Quoted(name), ..rest] -> Ok(#(name, rest))
    _ -> syntax(tokens)
  }
}

fn optional(tokens, keywords) {
  case list.length(tokens) >= list.length(keywords) {
    True -> {
      let #(start, rest) = list.split(tokens, list.length(keywords))
      case
        list.all(list.zip(start, keywords), fn(pair) { is(pair.0, pair.1) })
      {
        True -> #(True, rest)
        False -> #(False, tokens)
      }
    }
    False -> #(False, tokens)
  }
}

fn statement(tokens) -> Result(#(Statement, List(Token)), String) {
  case tokens {
    [Word(word), ..rest] ->
      case string.lowercase(word) {
        "create" -> create(rest)
        "drop" -> drop(rest)
        "insert" -> insert(rest)
        "select" -> select(rest)
        "update" -> update(rest)
        "delete" -> delete(rest)
        _ -> syntax(tokens)
      }
    _ -> syntax(tokens)
  }
}

fn create(tokens) {
  use rest <- keyword(tokens, "table")
  let #(if_not_exists, rest) = optional(rest, ["if", "not", "exists"])
  use #(table, rest) <- result.try(name(rest))
  use rest <- symbol(rest, "(")
  use #(definitions, rest) <- result.try(split(rest, 0, [], []))
  let columns =
    list.filter_map(definitions, fn(definition) {
      case definition {
        [Quoted(name), ..] -> Ok(name)
        [Word(word), ..] ->
          case string.lowercase(word) {
            "primary" | "unique" | "constraint" | "foreign" | "check" ->
              Error(Nil)
            name -> Ok(name)
          }
        _ -> Error(Nil)
      }
    })
  Ok(#(Create(table:, columns:, if_not_exists:), rest))
}

// Split a parenthesised list on its top level commas.
fn split(tokens, depth, current, done) {
  case tokens, depth {
    [], _ -> syntax(tokens)
    [Symbol(")"), ..rest], 0 ->
      Ok(#(list.reverse([list.reverse(current), ..done]), rest))
    [Symbol(","), ..rest], 0 ->
      split(rest, 0, [], [list.reverse(current), ..done])
    [Symbol("(") as token, ..rest], _ ->
      split(rest, depth + 1, [token, ..current], done)
    [Symbol(")") as token, ..rest], _ ->
      split(rest, depth - 1, [token, ..current], done)
    [token, ..rest], _ -> split(rest, depth, [token, ..current], done)
  }
}

fn drop(tokens) {
  use rest <- keyword(tokens, "table")
  let #(if_exists, rest) = optional(rest, ["if", "exists"])
  use #(table, rest) <- result.try(name(rest))
  Ok(#(Drop(table:, if_exists:), rest))
}

fn insert(tokens) {
  use rest <- keyword(tokens, "into")
  use #(table, rest) <- result.try(name(rest))
  use #(columns, rest) <- result.try(case rest {
    [Symbol("("), ..rest] -> {
      use #(columns, rest) <- result.map(names(rest, []))
      #(Some(columns), rest)
    }
    _ -> Ok(#(None, rest))
  })
  use rest <- keyword(rest, "values")
  use #(rows, rest) <- result.try(rows(rest, []))
  use #(returning, rest) <- result.try(returning(rest))
  Ok(#(Insert(table:, columns:, rows:, returning:), rest))
}

fn names(tokens, done) {
  use #(column, rest) <- result.try(name(tokens))
  case rest {
    [Symbol(","), ..rest] -> names(rest, [column, ..done])
    [Symbol(")"), ..rest] -> Ok(#(list.reverse([column, ..done]), rest))
    _ -> syntax(rest)
  }
}

fn rows(tokens, done) {
  use rest <- symbol(tokens, "(")
  use #(row, rest) <- result.try(operands(rest, []))
  case rest {
    [Symbol(","), ..rest] -> rows(rest, [row, ..done])
    _ -> Ok(#(list.reverse([row, ..done]), rest))
  }
}

fn operands(tokens, done) {
  use #(operand, rest) <- result.try(operand(tokens))
  case rest {
    [Symbol(","), ..rest] -> operands(rest, [operand, ..done])
    [Symbol(")"), ..rest] -> Ok(#(list.reverse([operand, ..done]), rest))
    _ -> syntax(rest)
  }
}

fn operand(tokens) {
  use #(operand, rest) <- result.map(case tokens {
    [Text(text), ..rest] -> Ok(#(Value(Some(text)), rest))
    [Number(number), ..rest] -> Ok(#(Value(Some(number)), rest))
    [Parameter(index), ..rest] -> Ok(#(Param(index), rest))
    [Quoted(name), ..rest] -> Ok(#(Column(name), rest))
    [Word(word), ..rest] ->
      case string.lowercase(word), rest {
        "null", _ -> Ok(#(Value(None), rest))
        "true", _ -> Ok(#(Value(Some("t")), rest))
        "false", _ -> Ok(#(Value(Some("f")), rest))
        "now", [Symbol("("), Symbol(")"), ..rest] -> Ok(#(Now, rest))
        "current_timestamp", _ -> Ok(#(Now, rest))
        name, _ -> Ok(#(Column(name), rest))
      }
    _ -> syntax(tokens)
  })
  // Casts are ignored, every value is text.
  case rest {
    [Symbol("::"), Word(_), ..rest] -> #(operand, rest)
    _ -> #(operand, rest)
  }
}

fn returning(tokens) {
  case tokens {
    [token, ..rest] ->
      case is(token, "returning") {
        True -> {
          use #(projection, rest) <- result.map(projection(rest))
          #(Some(projection), rest)
        }
        False -> Ok(#(None, tokens))
      }
    [] -> Ok(#(None, tokens))
  }
}

fn projection(tokens) {
  case tokens {
    [Symbol("*"), ..rest] -> Ok(#(All, rest))
    _ -> {
      use #(columns, rest) <- result.map(columns(tokens, []))
      #(Columns(columns), rest)
    }
  }
}

fn columns(tokens, done) {
  use #(expression, rest) <- result.try(case tokens {
    [Word(word), Symbol("("), Symbol("*"), Symbol(")"), ..rest] ->
      case string.lowercase(word) {
        "count" -> Ok(#(#(Count, "count"), rest))
        _ -> syntax(tokens)
      }
    _ -> {
      use #(operand, rest) <- result.map(operand(tokens))
      let name = case operand {
        Column(name) -> name
        Now -> "now"
        _ -> "?column?"
      }
      #(#(Operand(operand), name), rest)
    }
  })
  let #(expression, rest) = case rest {
    [as_, Word(alias), ..after] ->
      case is(as_, "as") {
        True -> #(#(expression.0, string.lowercase(alias)), after)
        False -> #(expression, rest)
      }
    [as_, Quoted(alias), ..after] ->
      case is(as_, "as") {
        True -> #(#(expression.0, alias), after)
        False -> #(expression, rest)
      }
    _ -> #(expression, rest)
  }
  case rest {
    [Symbol(","), ..rest] -> columns(rest, [expression, ..done])
    _ -> Ok(#(list.reverse([expression, ..done]), rest))
  }
}

fn select(tokens) {
  use #(projection, rest) <- result.try(projection(tokens))
  let #(from, rest) = optional(rest, ["from"])
  use #(from, rest) <- result.try(case from {
    True -> {
      use #(table, rest) <- result.map(name(rest))
      #(Some(table), rest)
    }
    False -> Ok(#(None, rest))
  })
  use #(where, rest) <- result.try(where(rest))
  let #(grouped, rest) = optional(rest, ["group", "by"])
  use #(group, rest) <- result.try(case grouped {
    True -> group(rest, [])
    False -> Ok(#([], rest))
  })
  let #(ordered, rest) = optional(rest, ["order", "by"])
  use #(order, rest) <- result.try(case ordered {
    True -> order(rest, [])
    False -> Ok(#([], rest))
  })
  let #(limited, rest) = optional(rest, ["limit"])
  use #(limit, rest) <- result.try(case limited, rest {
    True, [Number(number), ..rest] ->
      case int.parse(number) {
        Ok(limit) -> Ok(#(Some(limit), rest))
        Error(Nil) -> syntax(rest)
      }
    True, _ -> syntax(rest)
    False, _ -> Ok(#(None, rest))
  })
  Ok(#(Select(projection:, from:, where:, group:, order:, limit:), rest))
}

fn group(tokens, done) {
  use #(column, rest) <- result.try(name(tokens))
  case rest {
    [Symbol(","), ..rest] -> group(rest, [column, ..done])
    _ -> Ok(#(list.reverse([column, ..done]), rest))
  }
}

fn order(tokens, done) {
  use #(column, rest) <- result.try(name(tokens))
  let #(descending, rest) = case optional(rest, ["desc"]) {
    #(True, rest) -> #(True, rest)
    #(False, rest) -> #(False, optional(rest, ["asc"]).1)
  }
  let done = [#(column, descending), ..done]
  case rest {
    [Symbol(","), ..rest] -> order(rest, done)
    _ -> Ok(#(list.reverse(done), rest))
  }
}

fn update(tokens) {
  use #(table, rest) <- result.try(name(tokens))
  use rest <- keyword(rest, "set")
  use #(set, rest) <- result.try(assignments(rest, []))
  use #(where, rest) <- result.try(where(rest))
  use #(returning, rest) <- result.try(returning(rest))
  Ok(#(Update(table:, set:, where:, returning:), rest))
}

fn assignments(tokens, set) {
  use #(column, rest) <- result.try(name(tokens))
  use rest <- symbol(rest, "=")
  use #(value, rest) <- result.try(operand(rest))
  let set = [#(column, value), ..set]
  case rest {
    [Symbol(","), ..rest] -> assignments(rest, set)
    _ -> Ok(#(list.reverse(set), rest))
  }
}

fn delete(tokens) {
  use rest <- keyword(tokens, "from")
  use #(table, rest) <- result.try(name(rest))
  use #(where, rest) <- result.try(where(rest))
  use #(returning, rest) <- result.try(returning(rest))
  Ok(#(Delete(table:, where:, returning:), rest))
}

fn where(tokens) {
  case optional(tokens, ["where"]) {
    #(True, rest) -> disjunction(rest)
    #(False, rest) -> Ok(#(Always, rest))
  }
}

fn disjunction(tokens) {
  use #(left, rest) <- result.try(conjunction(tokens))
  case optional(rest, ["or"]) {
    #(True, rest) -> {
      use #(right, rest) <- result.map(disjunction(rest))
      #(Or(left, right), rest)
    }
    #(False, rest) -> Ok(#(left, rest))
  }
}

fn conjunction(tokens) {
  use #(left, rest) <- result.try(negation(tokens))
  case optional(rest, ["and"]) {
    #(True, rest) -> {
      use #(right, rest) <- result.map(conjunction(rest))
      #(And(left, right), rest)
    }
    #(False, rest) -> Ok(#(left, rest))
  }
}

fn negation(tokens) {
  case optional(tokens, ["not"]), tokens {
    #(True, rest), _ -> {
      use #(condition, rest) <- result.map(negation(rest))
      #(Not(condition), rest)
    }
    _, [Symbol("("), ..rest] -> {
      use #(condition, rest) <- result.try(disjunction(rest))
      use rest <- symbol(rest, ")")
      Ok(#(condition, rest))
    }
    _, _ -> comparison(tokens)
  }
}

fn comparison(tokens) {
  use #(left, rest) <- result.try(operand(tokens))
  case rest {
    [Symbol(op), ..rest]
      if op == "="
      || op == "!="
      || op == "<"
      || op == ">"
      || op == "<="
      || op == ">="
    -> {
      use #(right, rest) <- result.map(operand(rest))
      #(Compare(left, op, right), rest)
    }
    _ ->
      case
        optional(rest, ["is", "not", "null"]),
        optional(rest, ["is", "null"])
      {
        #(True, rest), _ -> Ok(#(IsNull(left, True), rest))
        _, #(True, rest) -> Ok(#(IsNull(left, False), rest))
        _, _ -> {
          let #(negated, rest) = optional(rest, ["not"])
          case rest {
            [like, ..rest] ->
              case is(like, "like") || is(like, "ilike") {
                True -> {
                  use #(pattern, rest) <- result.map(operand(rest))
                  let condition = Like(left, pattern, is(like, "ilike"))
                  case negated {
                    True -> #(Not(condition), rest)
                    False -> #(condition, rest)
                  }
                }
                False -> syntax(rest)
              }
            [] -> syntax(rest)
          }
        }
      }
  }
}

// Execution --------------------------------------------------------------------

type Row =
  List(#(String, Option(String)))

type Scope {
  Scope(params: List(Option(String)), now: Int)
}

fn execute(
  database: Database,
  statement: Statement,
  params: List(Option(String)),
  now: Int,
) -> Result(#(Database, Output), String) {
  let scope = Scope(params:, now:)
  case statement {
    Create(table:, columns:, if_not_exists:) ->
      case dict.has_key(database, table), if_not_exists {
        True, True -> Ok(#(database, Output("CREATE TABLE", 0, [], [])))
        True, False -> Error("relation \"" <> table <> "\" already exists")
        False, _ ->
          Ok(#(
            dict.insert(database, table, Table(columns:, rows: [])),
            Output("CREATE TABLE", 0, [], []),
          ))
      }
    Drop(table:, if_exists:) ->
      case dict.has_key(database, table), if_exists {
        True, _ ->
          Ok(#(dict.delete(database, table), Output("DROP TABLE", 0, [], [])))
        False, True -> Ok(#(database, Output("DROP TABLE", 0, [], [])))
        False, False -> Error("table \"" <> table <> "\" does not exist")
      }
    Insert(table: name, columns:, rows:, returning:) -> {
      use table <- result.try(table(database, name))
      let columns = option.unwrap(columns, table.columns)
      use Nil <- result.try(known(table, name, columns))
      use rows <- result.try(
        list.try_map(rows, fn(values) {
          use Nil <- result.try(
            case list.length(values) == list.length(columns) {
              True -> Ok(Nil)
              False ->
                Error(
                  "INSERT has a different number of values and target columns",
                )
            },
          )
          use values <- result.map(list.try_map(values, value(_, [], scope)))
          let given = list.zip(columns, values)
          list.map(table.columns, fn(column) {
            list.key_find(given, column) |> result.unwrap(None)
          })
        }),
      )
      let database =
        dict.insert(
          database,
          name,
          Table(..table, rows: list.append(table.rows, rows)),
        )
      use output <- result.map(returned(
        "INSERT",
        returning,
        table.columns,
        rows,
        scope,
      ))
      #(database, output)
    }
    Select(projection:, from:, where:, group:, order:, limit:) -> {
      use #(columns, rows) <- result.try(case from {
        Some(name) -> {
          use table <- result.map(table(database, name))
          #(table.columns, table.rows)
        }
        None -> Ok(#([], [[]]))
      })
      use rows <- result.try(filter(columns, rows, where, scope))
      use Nil <- result.try(known_columns(columns, group))
      let aggregate = case projection {
        Columns(expressions) -> list.any(expressions, fn(e) { e.0 == Count })
        All -> False
      }
      let groups = case group, aggregate {
        [], False -> list.map(rows, fn(row) { [row] })
        [], True -> [rows]
        keys, _ -> {
          let key = fn(row) {
            let named = list.zip(columns, row)
            list.map(keys, fn(k) { list.key_find(named, k) })
          }
          list.fold(rows, [], fn(groups, row) {
            case list.key_find(groups, key(row)) {
              Ok(members) ->
                list.key_set(groups, key(row), list.append(members, [row]))
              Error(Nil) -> list.append(groups, [#(key(row), [row])])
            }
          })
          |> list.map(fn(entry) { entry.1 })
        }
      }
      use items <- result.try(
        list.try_map(groups, project(projection, columns, _, scope)),
      )
      let fields = fields(projection, columns)
      use items <- result.map(sort(fields, columns, items, order))
      let rows =
        case limit {
          Some(limit) -> list.take(items, limit)
          None -> items
        }
        |> list.map(fn(item) { item.1 })
      #(database, Output("SELECT", list.length(rows), fields, rows))
    }
    Update(table: name, set:, where:, returning:) -> {
      use table <- result.try(table(database, name))
      use Nil <- result.try(known(table, name, list.map(set, fn(a) { a.0 })))
      use updated <- result.try(
        list.try_map(table.rows, fn(row) {
          let named = list.zip(table.columns, row)
          use matches <- result.try(matches(where, named, scope))
          case matches {
            False -> Ok(#(row, False))
            True -> {
              use values <- result.map(
                list.try_map(set, fn(assignment) {
                  use value <- result.map(value(assignment.1, named, scope))
                  #(assignment.0, value)
                }),
              )
              #(
                list.map(named, fn(cell) {
                  list.key_find(values, cell.0) |> result.unwrap(cell.1)
                }),
                True,
              )
            }
          }
        }),
      )
      let changed =
        list.filter_map(updated, fn(row) {
          case row.1 {
            True -> Ok(row.0)
            False -> Error(Nil)
          }
        })
      let database =
        dict.insert(
          database,
          name,
          Table(..table, rows: list.map(updated, fn(row) { row.0 })),
        )
      use output <- result.map(returned(
        "UPDATE",
        returning,
        table.columns,
        changed,
        scope,
      ))
      #(database, output)
    }
    Delete(table: name, where:, returning:) -> {
      use table <- result.try(table(database, name))
      use removed <- result.try(filter(table.columns, table.rows, where, scope))
      let kept =
        list.filter(table.rows, fn(row) { !list.contains(removed, row) })
      let database = dict.insert(database, name, Table(..table, rows: kept))
      use output <- result.map(returned(
        "DELETE",
        returning,
        table.columns,
        removed,
        scope,
      ))
      #(database, output)
    }
  }
}

fn table(database, name) {
  dict.get(database, name)
  |> result.replace_error("relation \"" <> name <> "\" does not exist")
}

fn known(table: Table, name, columns) {
  case list.find(columns, fn(c) { !list.contains(table.columns, c) }) {
    Ok(column) ->
      Error(
        "column \""
        <> column
        <> "\" of relation \""
        <> name
        <> "\" does not exist",
      )
    Error(Nil) -> Ok(Nil)
  }
}

fn returned(command, returning, columns, rows, scope) {
  case returning {
    Some(projection) -> {
      use items <- result.map(
        list.try_map(rows, fn(row) {
          project(projection, columns, [row], scope)
        }),
      )
      let rows = list.map(items, fn(item) { item.1 })
      Output(command, list.length(rows), fields(projection, columns), rows)
    }
    None -> Ok(Output(command, list.length(rows), [], []))
  }
}

fn filter(columns, rows, where, scope) {
  list.try_fold(rows, [], fn(kept, row) {
    use matched <- result.map(matches(where, list.zip(columns, row), scope))
    case matched {
      True -> [row, ..kept]
      False -> kept
    }
  })
  |> result.map(list.reverse)
}

// Rows are sorted by output fields first, then the columns of the table.
fn sort(
  fields: List(String),
  columns: List(String),
  items: List(#(Row, List(Option(String)))),
  order: List(#(String, Bool)),
) {
  use Nil <- result.map(known_columns(
    list.append(fields, columns),
    list.map(order, fn(key) { key.0 }),
  ))
  let lookup = fn(item: #(Row, List(Option(String))), key) {
    list.key_find(list.zip(fields, item.1), key)
    |> result.lazy_or(fn() { list.key_find(item.0, key) })
    |> result.unwrap(None)
  }
  list.sort(items, fn(a, b) {
    list.fold_until(order, order.Eq, fn(_, key) {
      let #(column, descending) = key
      let compared = nulls_last(lookup(a, column), lookup(b, column))
      let compared = case descending {
        False -> compared
        True -> order.negate(compared)
      }
      case compared {
        order.Eq -> list.Continue(order.Eq)
        decided -> list.Stop(decided)
      }
    })
  })
}

fn known_columns(columns, names) {
  case list.find(names, fn(name) { !list.contains(columns, name) }) {
    Ok(name) -> Error("column \"" <> name <> "\" does not exist")
    Error(Nil) -> Ok(Nil)
  }
}

fn nulls_last(a, b) {
  case a, b {
    None, None -> order.Eq
    None, Some(_) -> order.Gt
    Some(_), None -> order.Lt
    Some(a), Some(b) -> compare(a, b)
  }
}

// Numbers compare as numbers, everything else as text.
fn compare(a, b) {
  case number(a), number(b) {
    Ok(a), Ok(b) -> float.compare(a, b)
    _, _ -> string.compare(a, b)
  }
}

fn number(text) {
  case float.parse(text) {
    Ok(n) -> Ok(n)
    Error(Nil) -> int.parse(text) |> result.map(int.to_float)
  }
}

fn fields(projection, columns) {
  case projection {
    All -> columns
    Columns(expressions) -> list.map(expressions, fn(e) { e.1 })
  }
}

// The values of a group of rows, and the first row to sort by.
fn project(projection, columns, group, scope) {
  let named = case group {
    [first, ..] -> list.zip(columns, first)
    [] -> []
  }
  let count = Some(int.to_string(list.length(group)))
  use values <- result.map(case projection {
    All -> Ok(list.map(named, fn(cell) { cell.1 }))
    Columns(expressions) ->
      list.try_map(expressions, fn(e) {
        case e.0 {
          Count -> Ok(count)
          Operand(operand) -> value(operand, named, scope)
        }
      })
  })
  #(named, values)
}

fn value(operand, row: Row, scope: Scope) -> Result(Option(String), String) {
  case operand {
    Column(name) ->
      list.key_find(row, name)
      |> result.replace_error("column \"" <> name <> "\" does not exist")
    Value(value) -> Ok(value)
    Param(index) ->
      list.drop(scope.params, index - 1)
      |> list.first
      |> result.replace_error("there is no parameter $" <> int.to_string(index))
    Now -> Ok(Some(timestamp_text(scope.now)))
  }
}

// Times as Postgres prints a `timestamptz` in UTC.
fn timestamp_text(milliseconds: Int) -> String {
  timestamp.from_unix_seconds_and_nanoseconds(
    milliseconds / 1000,
    { milliseconds % 1000 } * 1_000_000,
  )
  |> timestamp.to_rfc3339(calendar.utc_offset)
  |> string.replace("T", " ")
  |> string.replace("Z", "+00")
}

fn matches(condition, row: Row, scope: Scope) -> Result(Bool, String) {
  case condition {
    Always -> Ok(True)
    Compare(left, op, right) -> {
      use left <- result.try(value(left, row, scope))
      use right <- result.map(value(right, row, scope))
      case left, right {
        Some(left), Some(right) -> {
          let compared = compare(left, right)
          case op {
            "=" -> compared == order.Eq
            "!=" -> compared != order.Eq
            "<" -> compared == order.Lt
            ">" -> compared == order.Gt
            "<=" -> compared != order.Gt
            _ -> compared != order.Lt
          }
        }
        _, _ -> False
      }
    }
    IsNull(operand, negated) -> {
      use value <- result.map(value(operand, row, scope))
      { value == None } != negated
    }
    Like(operand, pattern, insensitive) -> {
      use text <- result.try(value(operand, row, scope))
      use pattern <- result.map(value(pattern, row, scope))
      case text, pattern {
        Some(text), Some(pattern) ->
          case insensitive {
            True ->
              like(
                string.to_graphemes(string.lowercase(text)),
                string.to_graphemes(string.lowercase(pattern)),
              )
            False ->
              like(string.to_graphemes(text), string.to_graphemes(pattern))
          }
        _, _ -> False
      }
    }
    And(left, right) -> {
      use left <- result.try(matches(left, row, scope))
      use right <- result.map(matches(right, row, scope))
      left && right
    }
    Or(left, right) -> {
      use left <- result.try(matches(left, row, scope))
      use right <- result.map(matches(right, row, scope))
      left || right
    }
    Not(condition) -> result.map(matches(condition, row, scope), fn(b) { !b })
  }
}

fn like(text, pattern) {
  case pattern, text {
    [], [] -> True
    ["%", ..rest], _ ->
      like(text, rest)
      || case text {
        [_, ..text] -> like(text, pattern)
        [] -> False
      }
    ["_", ..rest], [_, ..text] -> like(text, rest)
    [p, ..rest], [c, ..text] if p == c -> like(text, rest)
    _, _ -> False
  }
}
