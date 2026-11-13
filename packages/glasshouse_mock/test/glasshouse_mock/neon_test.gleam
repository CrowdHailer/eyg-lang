import glasshouse_mock/neon
import gleam/dynamic/decode
import gleam/http
import gleam/http/request
import gleam/http/response
import gleam/json
import gleam/option.{None, Some}
import gleam/time/calendar
import gleam/time/timestamp

const seed =
  "
-- Signups to a newsletter.
CREATE TABLE signups (id integer PRIMARY KEY, email text NOT NULL, source varchar(20), created timestamptz);
INSERT INTO signups (id, email, source) VALUES
  (1, 'ada@example.com', 'blog'),
  (2, 'grace@example.com', 'talk'),
  (3, 'alan@example.com', NULL);
"

fn seeded() {
  let assert Ok(history) = neon.seed(neon.new(), seed, 1000)
  history
}

fn rows(history, sql, params) {
  let assert Ok(#(_, output)) =
    neon.query(history, sql, params, at: None, now: 1500)
  output.rows
}

pub fn select_test() {
  let assert Ok(#(_, output)) =
    neon.query(
      seeded(),
      "SELECT id, email FROM signups",
      [],
      at: None,
      now: 1500,
    )
  assert output.command == "SELECT"
  assert output.fields == ["id", "email"]
  assert output.rows
    == [
      [Some("1"), Some("ada@example.com")],
      [Some("2"), Some("grace@example.com")],
      [Some("3"), Some("alan@example.com")],
    ]
}

pub fn where_order_and_limit_test() {
  let history = seeded()
  assert rows(
      history,
      "select email from signups where id > 1 order by email limit 1",
      [],
    )
    == [[Some("alan@example.com")]]
  assert rows(
      history,
      "SELECT id FROM signups WHERE source IS NULL OR source = $1 ORDER BY id DESC",
      [Some("blog")],
    )
    == [[Some("3")], [Some("1")]]
  assert rows(
      history,
      "SELECT id FROM signups WHERE email LIKE '%ace%' AND NOT id = 1",
      [],
    )
    == [[Some("2")]]
  assert rows(
      history,
      "SELECT count(*) AS total FROM signups WHERE source IS NOT NULL",
      [],
    )
    == [[Some("2")]]
}

pub fn group_by_test() {
  let assert Ok(history) =
    neon.seed(
      seeded(),
      "INSERT INTO signups (id, email, source) VALUES (4, 'edsger@example.com', 'talk'), (5, 'barbara@example.com', 'talk')",
      1200,
    )
  let assert Ok(#(_, output)) =
    neon.query(
      history,
      "SELECT source, count(*) AS signups FROM signups GROUP BY source ORDER BY signups DESC, source",
      [],
      at: None,
      now: 1500,
    )
  assert output.fields == ["source", "signups"]
  assert output.rows
    == [
      [Some("talk"), Some("3")],
      [Some("blog"), Some("1")],
      [None, Some("1")],
    ]
  let assert Error("column \"missing\" does not exist") =
    neon.query(
      history,
      "SELECT count(*) FROM signups GROUP BY missing",
      [],
      at: None,
      now: 1500,
    )
}

pub fn numbers_compare_as_numbers_test() {
  let assert Ok(history) =
    neon.seed(
      seeded(),
      "INSERT INTO signups (id, email) VALUES (10, 'x@example.com')",
      1200,
    )
  assert rows(history, "SELECT id FROM signups ORDER BY id DESC LIMIT 2", [])
    == [[Some("10")], [Some("3")]]
}

pub fn writes_return_counts_and_rows_test() {
  let assert Ok(#(history, output)) =
    neon.query(
      seeded(),
      "UPDATE signups SET source = 'web' WHERE source IS NULL RETURNING id, source",
      [],
      at: None,
      now: 2000,
    )
  assert output.command == "UPDATE"
  assert output.rows == [[Some("3"), Some("web")]]
  let assert Ok(#(history, output)) =
    neon.query(
      history,
      "DELETE FROM signups WHERE id < $1",
      [Some("3")],
      at: None,
      now: 2001,
    )
  assert output.count == 2
  assert rows(history, "SELECT * FROM signups", [])
    == [[Some("3"), Some("alan@example.com"), Some("web"), None]]
}

pub fn queries_at_a_point_in_time_see_the_past_test() {
  let assert Ok(#(history, _)) =
    neon.query(
      seeded(),
      "INSERT INTO signups (id, email, created) VALUES (4, 'edsger@example.com', now())",
      [],
      at: None,
      now: 2000,
    )
  let count = fn(at) {
    let assert Ok(#(_, output)) =
      neon.query(history, "SELECT count(*) FROM signups", [], at:, now: 3000)
    output.rows
  }
  assert count(Some(1999)) == [[Some("3")]]
  assert count(Some(2000)) == [[Some("4")]]
  assert count(None) == [[Some("4")]]
  // Before the database was seeded.
  let assert Error("relation \"signups\" does not exist") =
    neon.query(
      history,
      "SELECT count(*) FROM signups",
      [],
      at: Some(10),
      now: 3000,
    )
}

pub fn time_travel_is_read_only_test() {
  let assert Error("cannot execute DELETE in a read-only transaction") =
    neon.query(seeded(), "DELETE FROM signups", [], at: Some(1000), now: 2000)
}

pub fn errors_are_postgres_like_test() {
  let history = seeded()
  let error = fn(sql) {
    let assert Error(reason) = neon.query(history, sql, [], at: None, now: 2000)
    reason
  }
  assert error("SELECT * FROM missing") == "relation \"missing\" does not exist"
  assert error("SELECT name FROM signups") == "column \"name\" does not exist"
  assert error("INSERT INTO signups (name) VALUES ('x')")
    == "column \"name\" of relation \"signups\" does not exist"
  assert error("SELEC 1") == "syntax error at or near \"SELEC\""
  assert error("SELECT 1; SELECT 2")
    == "cannot insert multiple commands into a prepared statement"
  assert error("SELECT $2") == "there is no parameter $2"
}

pub fn quoted_names_and_text_test() {
  let assert Ok(history) =
    neon.seed(
      neon.new(),
      "create table \"Notes\" (body text); insert into \"Notes\" values ('it''s here')",
      1,
    )
  assert rows(history, "select body from \"Notes\"", [])
    == [[Some("it's here")]]
}

// Use the ordinary HTTP contract; no service-specific EYG effect is needed.
fn request_for(query, params, connection) {
  request.new()
  |> request.set_scheme(http.Http)
  |> request.set_host("localhost")
  |> request.set_port(4400)
  |> request.set_method(http.Post)
  |> request.set_path("/sql")
  |> request.set_header("neon-connection-string", connection)
  |> request.set_header("neon-raw-text-output", "true")
  |> request.set_header("neon-array-mode", "true")
  |> request.set_body(<<
    {
      json.to_string(
        json.object([
          #("query", json.string(query)),
          #("params", json.array(params, json.string)),
        ]),
      )
    }:utf8,
  >>)
}

fn returned(response: response.Response(BitArray)) {
  let decoder = {
    use fields <- decode.field(
      "fields",
      decode.list(decode.field("name", decode.string, decode.success)),
    )
    use rows <- decode.field(
      "rows",
      decode.list(decode.list(decode.optional(decode.string))),
    )
    decode.success(#(fields, rows))
  }
  json.parse_bits(response.body, decoder)
}

pub fn ordinary_http_queries_test() {
  let #(_, response) =
    neon.handle(
      seeded(),
      request_for(
        "SELECT email FROM signups WHERE id = $1",
        ["2"],
        "postgresql://demo:demo@localhost:4400/demo",
      ),
      2000,
    )
  let assert Ok(#(fields, rows)) = returned(response)
  assert fields == ["email"]
  assert rows == [[Some("grace@example.com")]]
}

pub fn http_time_travel_is_read_only_test() {
  let assert Ok(#(history, _)) =
    neon.query(
      seeded(),
      "DELETE FROM signups",
      [],
      at: None,
      now: 1_791_889_260_000,
    )
  let before =
    timestamp.from_unix_seconds_and_nanoseconds(1_791_889_259, 999_000_000)
    |> timestamp.to_rfc3339(calendar.utc_offset)
  let connection =
    "postgresql://demo:demo@localhost:4400/demo?sslmode=require&options=neon_timestamp:"
    <> before
  let #(_, response) =
    neon.handle(
      history,
      request_for("SELECT count(*) FROM signups", [], connection),
      1_791_889_270_000,
    )
  let assert Ok(#(_, rows)) = returned(response)
  assert rows == [[Some("3")]]
  let #(_, response) =
    neon.handle(
      history,
      request_for("DELETE FROM signups", [], connection),
      1_791_889_270_000,
    )
  assert response.status == 400
  assert json.parse_bits(
      response.body,
      decode.field("message", decode.string, decode.success),
    )
    == Ok("cannot execute DELETE in a read-only transaction")
}
