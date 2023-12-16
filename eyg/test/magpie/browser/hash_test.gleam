import magpie/query
import magpie/browser/hash
import gleeunit/should

pub fn round_trip(query) {
  hash.encode(query)
  |> hash.decode()
}

pub fn empty_query_test() {
  let qs = [#([], [])]
  qs
  |> round_trip
  |> should.equal(Ok(qs))
}

pub fn literal_query_test() {
  let qs = [#([], [#(query.i(0), query.s("foo"), query.b(True))])]
  qs
  |> round_trip
  |> should.equal(Ok(qs))
}

pub fn reused_variables_test() {
  let qs = [
    #(
      ["a", "b", "c"],
      [
        #(query.v("a"), query.v("b"), query.v("a")),
        #(query.v("b"), query.v("c"), query.v("c")),
      ],
    ),
  ]
  qs
  |> round_trip
  |> should.equal(Ok(qs))
}

pub fn some_unused_variables_test() {
  let qs = [#(["x"], [#(query.v("a"), query.v("b"), query.v("x"))])]
  qs
  |> round_trip
  |> should.equal(Ok(qs))
}
