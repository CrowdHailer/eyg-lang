import gleam/javascript as js
import gleeunit/should

pub fn equality_test() {
  js.make_reference(0)
  |> js.reference_equal(js.make_reference(0))
  |> should.equal(False)

  let ref = js.make_reference(0)
  js.reference_equal(ref, ref)
  |> should.equal(True)
}
