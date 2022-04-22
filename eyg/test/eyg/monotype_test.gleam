import gleam/option.{None, Some}
import eyg/typer/monotype.{
  Binary, Function, Native, Record, Tuple, Unbound, to_string,
}

fn native_to_string(_) {
  "N"
}

pub fn type_to_string_test() {
  let "Binary" = to_string(Binary, native_to_string)
  let "()" = to_string(Tuple([]), native_to_string)
  let "(Binary, ())" = to_string(Tuple([Binary, Tuple([])]), native_to_string)
  let "{}" = to_string(Record([], None), native_to_string)
  let "{foo: Binary, bar: ()}" =
    to_string(
      Record([#("foo", Binary), #("bar", Tuple([]))], None),
      native_to_string,
    )
  let "() -> Binary" = to_string(Function(Tuple([]), Binary), native_to_string)
}
