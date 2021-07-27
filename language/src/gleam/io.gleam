// Don't call this just io module messes up predefined modules

if erlang {
  external type DoNotLeak

  external fn erl_print(String, List(a)) -> DoNotLeak =
    "io" "fwrite"

  pub fn debug(term: anything) -> anything {
    erl_print("~tp\n", [term])
    term
  }
}

if javascript {
  external type DoNotLeak

  external fn console_log(term: anything) -> DoNotLeak =
    "" "window.console.log"

  pub fn debug(term: anything) -> anything {
    console_log(term)
    term
  }
}