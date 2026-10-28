import overlay/web/view

pub fn summary_test() {
  assert view.summary("5") == "5"
  assert view.summary("Output:\nhello\n\nResult:\n{}") == "Result: {}"
  assert view.summary("\ntype mismatch\nmore") == "type mismatch"
}
