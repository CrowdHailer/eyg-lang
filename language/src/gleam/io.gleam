// Don't call this just io module messes up predefined modules
external type DoNotLeak

external fn erl_print(String, List(a)) -> DoNotLeak =
  "io" "fwrite"

pub fn debug(term: anything) -> anything {
  erl_print("~tp\n", [term])
  term
}
