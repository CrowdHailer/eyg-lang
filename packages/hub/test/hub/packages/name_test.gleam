import gleam/list
import gleam/string
import hub/packages/name

pub fn accepts_reasonable_names_test() {
  use valid <- list.each([
    "eyg", "json", "my-package", "a", "http2", "a1b2c3", "long-ish-name",
  ])
  assert name.valid(valid) == True
}

pub fn rejects_bad_names_test() {
  use invalid <- list.each([
    "",
    "-leading",
    "trailing-",
    "double--hyphen",
    "UPPER",
    "has space",
    "under_score",
    "1leading-digit",
    "emoji😀",
    "dot.separated",
    string.repeat("a", 65),
  ])
  assert name.valid(invalid) == False
}

pub fn max_length_boundary_test() {
  assert name.valid(string.repeat("a", 64)) == True
  assert name.valid(string.repeat("a", 65)) == False
}
