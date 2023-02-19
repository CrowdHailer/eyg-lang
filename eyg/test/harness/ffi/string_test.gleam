import eygir/expression as e
import eyg/runtime/interpreter as r
import harness/ffi/string
import eyg/provider
import gleeunit/should

pub fn string_append_test() {
  let var = "ffi_append"
  let source =
    e.Apply(e.Apply(e.Variable(var), e.Binary("fizz")), e.Binary("buzz"))
  r.eval(source, [#(var, string.append().1)], provider.noop, r.Value)
  |> should.equal(r.Value(r.Binary("fizzbuzz")))
}
