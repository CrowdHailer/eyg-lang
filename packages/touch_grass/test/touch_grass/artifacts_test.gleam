import eyg/interpreter/value as v
import gleam/dict
import gleam/option.{None, Some}
import touch_grass/acquire
import touch_grass/mount

pub fn acquisition_sources_round_trip_and_require_explicit_expected_test() {
  let inputs = [
    acquire.Input(
      acquire.Git("https://example.com/repo.git", Some("master")),
      None,
    ),
    acquire.Input(
      acquire.Git("https://example.com/repo.git", None),
      Some("tree"),
    ),
    acquire.Input(acquire.Http("https://example.com/data"), None),
  ]
  let assert [a, b, c] = inputs
  assert acquire.decode(acquire.input_value(a)) == Ok(a)
  assert acquire.decode(acquire.input_value(b)) == Ok(b)
  assert acquire.decode(acquire.input_value(c)) == Ok(c)
  let missing =
    v.Record(dict.from_list([#("source", acquire.source_value(a.source))]))
  let assert Error(_) = acquire.decode(missing)
}

pub fn mount_requires_root_and_path_test() {
  let value =
    v.Record(
      dict.from_list([#("root", v.String("root")), #("path", v.String("repo"))]),
    )
  assert mount.decode(value) == Ok(mount.Input("root", "repo"))
  let assert Error(_) = mount.decode(v.String("repo"))
  assert mount.encode(Error("already exists"))
    == v.error(v.String("already exists"))
  assert acquire.encode(Ok(acquire.Receipt("root", "commit")))
    == v.ok(
      v.Record(
        dict.from_list([
          #("root", v.String("root")),
          #("resolved", v.String("commit")),
        ]),
      ),
    )
}
