import gleam/io
import gleam/option.{None, Some}
// only use t.version
import eyg/typer/monotype.{Binary,
  Function, Native, Record, Tuple, Unbound} as t
import eyg/editor/type_info.{to_string}

pub fn type_to_string_test() {
  let "Binary" = to_string(Binary)
  let "()" = to_string(Tuple([]))
  let "(Binary, ())" = to_string(Tuple([Binary, Tuple([])]))
  let "{}" = to_string(Record([], None))
  let "{foo: Binary, bar: ()}" =
    to_string(Record([#("foo", Binary), #("bar", Tuple([]))], None))

  let "[Foo () | Bar Binary]" =
    to_string(t.Union([#("Foo", t.Tuple([])), #("Bar", t.Binary)], None))
  let "[Foo () | ..0]" = to_string(t.Union([#("Foo", t.Tuple([]))], Some(0)))
  let "() -> Binary" = to_string(Function(Tuple([]), Binary, t.empty))
  let "() -> Binary" = to_string(Function(Tuple([]), Binary, t.Unbound(0)))
  let effects =
    t.Union(
      [
        #("Abort", t.Function(t.Tuple([]), t.Tuple([]), t.Union([], Some(0)))),
        #(
          "Log",
          t.Recursive(0, t.Function(t.Binary, t.Tuple([]), t.Unbound(0))),
        ),
      ],
      None,
    )
  let "() -> <Abort () -> () | Log Binary -> ()> Binary" =
    to_string(Function(Tuple([]), Binary, effects))
  // Need to think more about handling the dots
  // let "() ->{Abort () | ..1} Binary" = to_string(Function(Tuple([]), Binary, t.Union([#("Abort", t.Tuple([]))], Some(1))))
}
