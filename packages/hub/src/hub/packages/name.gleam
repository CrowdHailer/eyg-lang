//// Package naming policy.

import gleam/list
import gleam/string

const max_length = 64

const lower = "abcdefghijklmnopqrstuvwxyz"

const digits = "0123456789"

/// A valid package name is 1..64 characters of lowercase letters, digits and
/// single hyphens, starting with a letter and not ending with a hyphen.
pub fn valid(name: String) -> Bool {
  case string.to_graphemes(name) {
    [] -> False
    [first, ..] as all ->
      list.length(all) <= max_length
      && is_letter(first)
      && list.all(all, is_allowed)
      && !string.ends_with(name, "-")
      && !string.contains(name, "--")
  }
}

fn is_letter(grapheme: String) -> Bool {
  string.contains(lower, grapheme)
}

fn is_allowed(grapheme: String) -> Bool {
  string.contains(lower, grapheme)
  || string.contains(digits, grapheme)
  || grapheme == "-"
}
