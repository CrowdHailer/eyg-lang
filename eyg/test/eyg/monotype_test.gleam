import gleam/option.{None, Some}
import eyg/typer/monotype.{
  Binary, Function, Native, Row, Tuple, Unbound, to_string,
}

pub fn type_to_string_test() {
  let "Binary" = to_string(Binary)
  let "Foo" = to_string(Native("Foo"))
  let "()" = to_string(Tuple([]))
  let "(Binary, ())" = to_string(Tuple([Binary, Tuple([])]))
  let "{}" = to_string(Row([], None))
  let "{foo: Binary, bar: ()}" =
    to_string(Row([#("foo", Binary), #("bar", Tuple([]))], None))
  let "() -> Binary" = to_string(Function(Tuple([]), Binary))
}
