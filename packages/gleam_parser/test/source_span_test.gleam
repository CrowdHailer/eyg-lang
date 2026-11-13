import eyg/parser
import gleam/list
import gleam/string

pub fn calls_include_the_actual_closing_parenthesis_test() {
  list.each(
    [
      "!equal(\"é\", \"é\")",
      "!equal(\"\\n\", \"\\n\")",
      "!equal(1, 1   )",
      "f(1)(2  )",
    ],
    fn(source) {
      let assert Ok(#(_, at)) = parser.all_from_string(source)
      assert at == #(0, string.byte_size(source))
    },
  )
}
