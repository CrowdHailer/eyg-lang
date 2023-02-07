import magpie/store/in_memory.{B, I, L, S}
import magpie/store/json
import gleeunit/should

pub fn function_name_test() -> Nil {
  let triples = [
    #(0, "boolean", B(True)),
    #(0, "integer", I(10)),
    #(1, "string", S("Hello, World!")),
    #(1, "list", L([S("foo"), S("bar")])),
  ]

  triples
  |> json.to_string()
  |> json.from_string()
  |> should.equal(Ok(triples))
}
