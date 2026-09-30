import dag_json
import eyg/compiler
import eyg/ir/cid
import eyg/ir/dag_json as codec
import eyg/ir/tree as ir
import gleam/crypto
import gleam/dict
import gleam/dynamic/decode
import gleam/int
import gleam/io
import gleam/json
import gleam/list
import gleam/result
import gleam/string
import gleeunit/should
import midas/continuation
import multiformats/cid/v1
import plinth/browser/window
import simplifile

type Value {
  Integer(Int)
  String(String)
  Binary(BitArray)
  LinkedList(List(Value))
  Record(dict.Dict(String, Value))
  Tagged(String, Value)
}

type Fixture {
  Fixture(
    name: String,
    source: ir.Node(Nil),
    effects: List(Effect),
    final: Result(Value, dict.Dict(String, String)),
  )
}

type Effect {
  Effect(label: String, lift: Value, reply: Value)
}

// The same fixture schema as gleam_interpreter's evaluation suite.
fn value_decoder() {
  use <- decode.recursive
  use fields <- decode.then(decode.dict(decode.string, decode.dynamic))
  case dict.keys(fields) {
    ["binary"] -> {
      use bytes <- decode.field("binary", dag_json.decode_bytes())
      decode.success(Binary(bytes))
    }
    ["integer"] -> {
      use value <- decode.field("integer", decode.int)
      decode.success(Integer(value))
    }
    ["string"] -> {
      use value <- decode.field("string", decode.string)
      decode.success(String(value))
    }
    ["list"] -> {
      use items <- decode.field("list", decode.list(value_decoder()))
      decode.success(LinkedList(items))
    }
    ["record"] -> {
      use fields <- decode.field(
        "record",
        decode.dict(decode.string, value_decoder()),
      )
      decode.success(Record(fields))
    }
    ["tagged"] -> {
      use tagged <- decode.field("tagged", {
        use label <- decode.field("label", decode.string)
        use value <- decode.field("value", value_decoder())
        decode.success(Tagged(label, value))
      })
      decode.success(tagged)
    }
    _ -> decode.failure(Integer(0), "spec value")
  }
}

fn effect_decoder() {
  use label <- decode.field("label", decode.string)
  use lift <- decode.field("lift", value_decoder())
  use reply <- decode.field("reply", value_decoder())
  decode.success(Effect(label, lift, reply))
}

fn expectation_decoder() {
  decode.one_of(
    decode.field("value", decode.map(value_decoder(), Ok), decode.success),
    [
      decode.field(
        "break",
        {
          use reason <- decode.map(decode.dict(decode.string, decode.string))
          Error(reason)
        },
        decode.success,
      ),
    ],
  )
}

fn suite_decoder() {
  decode.list({
    use name <- decode.field("name", decode.string)
    use source <- decode.field("source", codec.decoder(Nil))
    use effects <- decode.optional_field(
      "effects",
      [],
      decode.list(effect_decoder()),
    )
    use expected <- decode.map(expectation_decoder())
    Fixture(name, source, effects, expected)
  })
}

fn bytes_list(bytes) {
  case bytes {
    <<byte:8, rest:bits>> -> [byte, ..bytes_list(rest)]
    _ -> []
  }
}

// The compiler uses linked arrays for lists and Uint8Array for binaries.
// The eval wrapper serializes binaries with an explicit marker so they cannot
// accidentally compare equal to lists or records.
fn value_json(value: Value) -> json.Json {
  case value {
    Integer(i) -> json.int(i)
    String(s) -> json.string(s)
    Binary(bytes) ->
      json.object([#("$binary", json.array(bytes_list(bytes), json.int))])
    LinkedList(items) ->
      list.fold_right(items, json.preprocessed_array([]), fn(tail, item) {
        json.preprocessed_array([value_json(item), tail])
      })
    Record(fields) -> json.dict(fields, fn(k) { k }, value_json)
    Tagged(label, inner) ->
      json.object([#("$T", json.string(label)), #("$V", value_json(inner))])
  }
}

fn as_dynamic(value) {
  value |> json.to_string |> json.parse(decode.dynamic) |> should.be_ok
}

fn check_fixture(fixture) -> Result(Nil, String) {
  let Fixture(_, source, effects, expected) = fixture
  let compiled = compiler.to_js(source, dict.new(), "$effect")
  let replies =
    json.array(effects, fn(e) { value_json(e.reply) }) |> json.to_string
  // Keep the host boundary small: record every effect, supply fixture replies,
  // and catch only structured language breaks. Unexpected JS errors fail eval.
  let script = "(() => {
  const effects = [];
  const replies = JSON.parse(" <> { replies |> json.string |> json.to_string } <> ", (_, v) => v && Object.hasOwn(v, '$binary') ? new Uint8Array(v.$binary) : v);
  const $effect = (label, value) => {
    effects.push({label, value});
    if (effects.length > replies.length) throw new Error('Unexpected effect ' + label);
    return replies[effects.length - 1];
  };
  let outcome;
  try { outcome = {value: eval(" <> {
      compiled |> json.string |> json.to_string
    } <> ")}; }
  catch (error) {
    if (!error || !error.eygBreak) throw error;
    outcome = {break: error.eygBreak};
  }
  return JSON.parse(JSON.stringify({...outcome, effects}, (_, v) => v instanceof Uint8Array ? {$binary: Array.from(v)} : v));
})()"
  use actual <- result.try(window.eval(script))
  let expected =
    json.object([
      case expected {
        Ok(value) -> #("value", value_json(value))
        Error(reason) -> #("break", json.dict(reason, fn(k) { k }, json.string))
      },
      #(
        "effects",
        json.array(effects, fn(e) {
          json.object([
            #("label", json.string(e.label)),
            #("value", value_json(e.lift)),
          ])
        }),
      ),
    ])
    |> as_dynamic
  case actual == expected {
    True -> Ok(Nil)
    False -> {
      Error(
        "expected "
        <> string.inspect(expected)
        <> ", got "
        <> string.inspect(actual),
      )
    }
  }
}

fn check_ir_suite(path) {
  let fixtures =
    simplifile.read(path)
    |> should.be_ok
    |> json.parse(
      decode.list({
        use name <- decode.field("name", decode.string)
        use source <- decode.field("source", codec.decoder(Nil))
        use expected <- decode.field("cid", decode.string)
        decode.success(#(name, source, expected))
      }),
    )
    |> should.be_ok
  list.is_empty(fixtures) |> should.be_false
  let failures =
    list.filter_map(fixtures, fn(fixture) {
      let #(name, source, expected) = fixture
      let calculated =
        cid.from_tree(source, fn(bytes) {
          continuation.return(crypto.hash(crypto.Sha256, bytes))
        })(v1.to_string)
      let roundtrip =
        source |> codec.to_string |> json.parse(codec.decoder(Nil))
      case calculated == expected && roundtrip == Ok(source) {
        True -> Error(Nil)
        False -> Ok(path <> ": " <> name <> ": CID or roundtrip mismatch")
      }
    })
  #(list.length(fixtures), failures)
}

pub fn all_spec_suites_test() {
  let files =
    simplifile.get_files("../../spec")
    |> should.be_ok
    |> list.filter(string.ends_with(_, "_suite.json"))
    |> list.sort(string.compare)
  list.is_empty(files) |> should.be_false
  let #(count, failures) =
    list.fold(files, #(0, []), fn(acc, path) {
      let #(count, failures) = case string.ends_with(path, "/ir_suite.json") {
        True -> check_ir_suite(path)
        False -> {
          let fixtures =
            simplifile.read(path)
            |> should.be_ok
            |> json.parse(suite_decoder())
            |> should.be_ok
          list.is_empty(fixtures) |> should.be_false
          let failures =
            list.filter_map(fixtures, fn(fixture) {
              case check_fixture(fixture) {
                Ok(Nil) -> Error(Nil)
                Error(message) ->
                  Ok(path <> ": " <> fixture.name <> ": " <> message)
              }
            })
          #(list.length(fixtures), failures)
        }
      }
      #(acc.0 + count, list.append(acc.1, failures))
    })
  io.println(
    "Spec: "
    <> int.to_string(count - list.length(failures))
    <> "/"
    <> int.to_string(count)
    <> " fixtures passed across "
    <> int.to_string(list.length(files))
    <> " suites",
  )
  list.each(failures, io.println)
  list.is_empty(failures) |> should.be_true
}
