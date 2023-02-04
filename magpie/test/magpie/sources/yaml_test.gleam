import magpie/sources/yaml
import gleeunit/should
import magpie/store/in_memory.{B, I, L, S}

pub fn loading_strings_test() {
  let source =
    "
    foo: hey
    bar: \"you\"
    "
  yaml.parse(source)
  |> should.equal(Ok([#(0, "foo", S("hey")), #(0, "bar", S("you"))]))
}

pub fn loading_booleans_test() {
  let source =
    "
    foo: true
    bar: False
    "
  yaml.parse(source)
  |> should.equal(Ok([#(0, "foo", B(True)), #(0, "bar", B(False))]))
}

pub fn loading_numbers_test() {
  let source =
    "
    foo: 101
    bar: 1E2
    "
  yaml.parse(source)
  |> should.equal(Ok([#(0, "foo", I(101)), #(0, "bar", I(100))]))
}

pub fn loading_lists_test() {
  let source =
    "
    foo:
      - 101
      - foo: 2
    "
  yaml.parse(source)
  |> should.equal(Ok([#(1, "foo", I(2)), #(0, "foo", L([I(101), I(1)]))]))
}

pub fn loading_nested_test() {
  let source =
    "
    foo:
      bar:
        baz: 1
        buz: 2
    "
  yaml.parse(source)
  |> should.equal(Ok([
    #(1, "bar", I(2)),
    #(2, "baz", I(1)),
    #(2, "buz", I(2)),
    #(0, "foo", I(1)),
  ]))
}
