import loam/system
import simplifile

pub fn resolve_relative_paths_test() {
  assert system.resolve_relative("/project/src", "../data/./file")
    == Ok("/project/data/file")
  assert system.resolve_relative("/project/src", "/other/file")
    == Ok("/other/file")
  assert system.resolve_relative("src", "../data/file") == Ok("data/file")
  // assert system.resolve_relative("/project", "data/") == Ok("/project/data/")
  assert system.resolve_relative("/project", "../") == Ok("/")
  assert system.resolve_relative("src", "../") == Ok("")
}

pub fn unresolvable_paths_are_invalid_arguments_test() {
  assert system.resolve_relative("/project", "../../file")
    == Error(simplifile.Einval)
  assert system.resolve_relative("/project", "/../file")
    == Error(simplifile.Einval)
  assert system.resolve_relative("src", "../../file")
    == Error(simplifile.Einval)
}
