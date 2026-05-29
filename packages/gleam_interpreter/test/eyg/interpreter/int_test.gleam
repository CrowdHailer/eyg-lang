import eyg/interpreter/break
import eyg/interpreter/expression as r
import eyg/interpreter/value as v
import eyg/ir/integer
import eyg/ir/tree as ir
import gleeunit/should

pub fn int_parse_in_range_test() {
  ir.apply(ir.builtin("int_parse"), ir.string("5"))
  |> r.execute([])
  |> should.equal(Ok(v.ok(v.Integer(5))))
}

pub fn int_parse_out_of_safe_range_test() {
  let result =
    ir.apply(ir.builtin("int_parse"), ir.string("999999999999999000000"))
    |> r.execute([])
  // need to multiple two smaller literals or will get Gleam warning
  let n = 999_999_999_999_999 * 1_000_000
  case integer.is_safe(n) {
    True -> {
      assert Ok(v.Integer(n)) == result
    }
    False -> {
      let assert Error(#(reason, _, _, _)) = result
      assert break.Unrepresentable(builtin: "int_parse", args: [
          v.String(value: "999999999999999000000"),
        ])
        == reason
    }
  }
}

pub fn arithmetic_in_range_test() {
  ir.apply(ir.apply(ir.builtin("int_add"), ir.integer(2)), ir.integer(3))
  |> r.execute([])
  |> should.equal(Ok(v.Integer(5)))
}

pub fn arithmetic_out_of_safe_range_test() {
  let result =
    ir.apply(
      ir.apply(ir.builtin("int_add"), ir.integer(9_007_199_254_740_991)),
      ir.integer(9_007_199_254_740_991),
    )
    |> r.execute([])
  let n = 9_007_199_254_740_991 + 9_007_199_254_740_991
  case integer.is_safe(n) {
    True -> {
      assert Ok(v.Integer(n)) == result
    }
    False -> {
      let assert Error(#(reason, _, _, _)) = result
      assert break.Unrepresentable(builtin: "int_add", args: [
          v.Integer(value: 9_007_199_254_740_991),
          v.Integer(value: 9_007_199_254_740_991),
        ])
        == reason
    }
  }
}
