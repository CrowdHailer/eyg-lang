import dag_json
import eyg/interpreter/break
import eyg/interpreter/expression as r
import eyg/interpreter/state
import eyg/interpreter/value as v
import eyg/ir/dag_json as codec
import eyg/ir/tree as ir
import gleam/dynamic/decode
import gleam/io
import gleam/list
import gleam/string
import gleeunit/should
import simplifile

type Value =
  state.Value(Nil)

type Fixture {
  Fixture(
    name: String,
    source: ir.Node(Nil),
    effects: List(Effect),
    final: Result(Value, state.Reason(Nil)),
  )
}

type Effect {
  Effect(label: String, lift: Value, reply: Value)
}

fn value_decoder() {
  use <- decode.recursive
  decode.one_of(
    {
      use bytes <- decode.field("binary", decode.bit_array)
      decode.success(v.Binary(bytes))
    },
    [
      {
        use integer <- decode.field("integer", decode.int)
        decode.success(v.Integer(integer))
      },
      {
        use string <- decode.field("string", decode.string)
        decode.success(v.String(string))
      },
      {
        use items <- decode.field("list", decode.list(value_decoder()))
        decode.success(v.LinkedList(items))
      },
      {
        use items <- decode.field(
          "record",
          decode.dict(decode.string, value_decoder()),
        )
        decode.success(v.Record(items))
      },
      {
        use tagged <- decode.field("tagged", {
          use label <- decode.field("label", decode.string)
          use value <- decode.field(
            "value",
            decode.one_of(
              {
                // This should be a recursive call to value_decoder,
                // however that crashes with a stack overflow.
                use integer <- decode.field("integer", decode.int)
                decode.success(v.Integer(integer))
              },
              [
                {
                  use items <- decode.field(
                    "record",
                    decode.dict(decode.string, value_decoder()),
                  )
                  decode.success(v.Record(items))
                },
                {
                  use string <- decode.field("string", decode.string)
                  decode.success(v.String(string))
                },
                {
                  use items <- decode.field(
                    "list",
                    decode.list(value_decoder()),
                  )
                  decode.success(v.LinkedList(items))
                },
              ],
            ),
          )
          decode.success(v.Tagged(label, value))
        })
        decode.success(tagged)
      },
    ],
  )
}

fn effect_decoder() {
  use label <- decode.field("label", decode.string)
  use lift <- decode.field("lift", value_decoder())
  use reply <- decode.field("reply", value_decoder())

  decode.success(Effect(label, lift, reply))
}

fn expectation_decoder() {
  decode.one_of(
    {
      use expected <- decode.field("value", value_decoder())
      decode.success(Ok(expected))
    },
    [
      {
        use expected <- decode.field(
          "break",
          decode.one_of(
            {
              use var <- decode.field("UndefinedVariable", decode.string)
              decode.success(Error(break.UndefinedVariable(var)))
            },
            [
              {
                use identifer <- decode.field("UndefinedBuiltin", decode.string)
                decode.success(Error(break.UndefinedBuiltin(identifer)))
              },
              {
                use _ <- decode.field("NotImplemented", decode.string)
                decode.success(Error(break.Vacant))
              },
            ],
          ),
        )
        decode.success(expected)
      },
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

fn check_evaluated(name, got, expected) {
  case got, expected {
    Ok(got), Ok(expected) -> should.equal(got, expected)
    Error(#(got, _, _, _)), Error(expected) -> should.equal(got, expected)

    Error(#(reason, _, _, _)), Ok(_) -> {
      panic as { name <> " failed because " <> string.inspect(reason) }
    }
    _, _ -> {
      let _ = io.debug(got)
      panic as { name <> " failed" }
    }
  }
}

pub fn evaluation_suite_test() {
  let dir = "../../spec/evaluation/"
  let tests =
    ["core_suite.json", "builtins_suite.json", "effects_suite.json"]
    |> list.map(fn(file) {
      simplifile.read_bits(dir <> file)
      |> should.be_ok
      |> dag_json.decode()
      |> should.be_ok
      |> decode.run(suite_decoder())
      |> should.be_ok
    })
    |> list.flatten

  list.map(tests, fn(fixture) {
    let Fixture(name, source, effects, expected) = fixture
    let got = r.execute(source, [])
    let final =
      list.fold(effects, got, fn(return, expected) {
        let Effect(label, value, reply) = expected
        case return {
          Error(#(break.UnhandledEffect(l, v), _meta, env, k))
            if l == label && v == value
          -> r.resume(reply, env, k)
          _ ->
            panic as {
              "did not raise correct effect" <> string.inspect(return)
            }
        }
      })
    check_evaluated(name, final, expected)
  })
}
