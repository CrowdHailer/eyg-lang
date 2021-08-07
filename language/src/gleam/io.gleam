if erlang {
  // Don't call this just io module messes up predefined modules
  external type DoNotLeak

  external fn erl_print(String, List(a)) -> DoNotLeak =
    "io" "fwrite"

  pub fn debug(term: anything) -> anything {
    erl_print("~tp\n", [term])
    term
  }
}

if erlang {
  pub fn print(string: String) -> Nil {
    do_print(string)
  }

  fn do_print(string: String) -> Nil {
    erl_print(string, [])
    Nil
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
