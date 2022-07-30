import gleam/option.{None, Some}
import eyg/typer/monotype.{Binary, Function, Native, Record, Tuple, Unbound}
import eyg/editor/type_info.{to_string}

pub fn type_to_string_test() {
  let "Binary" = to_string(Binary, )
  let "()" = to_string(Tuple([]), )
  let "(Binary, ())" = to_string(Tuple([Binary, Tuple([])]), )
  let "{}" = to_string(Record([], None), )
  let "{foo: Binary, bar: ()}" =
    to_string(
      Record([#("foo", Binary), #("bar", Tuple([]))], None),
      
    )
  let "() -> Binary" = to_string(Function(Tuple([]), Binary), )
}
