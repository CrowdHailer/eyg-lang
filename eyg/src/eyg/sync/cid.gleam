import eygir/encode

@external(javascript, "../../browser_ffi.mjs", "hashCode")
pub fn hash_code(str: String) -> String

pub fn for_expression(expression) {
  //   let expression = annotated.drop_annotation(expression)
  // subtle.digest(<<string.inspect(expression):utf8>>)
  // |> promise.map(io.debug)
  // |> promise.map(result.unwrap(_, <<>>))
  // |> promise.map(bit_array.base16_encode(_))
  // |> promise.map(io.debug)
  "h" <> hash_code(encode.to_json(expression))
}
