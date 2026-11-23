import cloud/artifacts
import cloud/box
import cloud/file_system
import cloud/helpers
import cloud/shell_helpers

const page =
  "perform WriteFile({path: \"/page.html\", contents: !string_to_binary(\"<p>hi</p>\")})"

pub fn files_a_shell_changed_test() {
  use context <- helpers.context()
  let shell = shell_helpers.shell(context)
  let assert Ok(#(Ok(_), [])) = shell_helpers.run(context, shell, page)
  // A change in more than one segment, the files are listed in the order they were last changed.
  let assert Ok(#(Ok(_), [])) =
    shell_helpers.run(
      context,
      shell,
      "let _ = perform WriteFile({path: \"/a.txt\", contents: !string_to_binary(\"a\")})
let _ = perform Sleep(0)
perform WriteFile({path: \"/page.html\", contents: !string_to_binary(\"<p>again</p>\")})",
    )
  // Changes of code that fails, or that the box rejects, are discarded.
  let assert Ok(#(Error(_), [])) =
    shell_helpers.run(
      context,
      shell,
      "let _ = perform WriteFile({path: \"/failed.txt\", contents: !string_to_binary(\"x\")})
!int_add(1, \"x\")",
    )
  let assert Ok(#(Error(_), [])) =
    shell_helpers.run(
      context,
      shell,
      "perform WriteFile({path: \"/bad.eyg\", contents: !string_to_binary(\"let x =\")})",
    )
  // Changes made by others are not the shell's.
  let assert Ok(_) =
    box.change(context, shell.box, fn(root) {
      file_system.write(root, "/other.txt", <<"o">>)
    })
  let entries = shell_helpers.entries(context, shell)
  let assert Ok(changed) = artifacts.changed(entries, context.state)
  assert changed == ["/a.txt", "/page.html"]

  let assert Ok(home) = box.latest(context, shell.box)
  assert Ok(<<"<p>again</p>">>)
    == artifacts.read(home.root, "/page.html", context.state)
  assert Ok(<<"a">>) == artifacts.read(home.root, "a.txt", context.state)
  assert Error(Nil) == artifacts.read(home.root, "/missing", context.state)
}

pub fn content_type_test() {
  assert "text/html; charset=utf-8" == artifacts.content_type("/a/index.HTML")
  assert "image/svg+xml" == artifacts.content_type("/logo.svg")
  assert "text/plain; charset=utf-8" == artifacts.content_type("/Makefile")
  assert "text/plain; charset=utf-8" == artifacts.content_type("/main.eyg")
  assert artifacts.viewable("/index.html")
  assert artifacts.viewable("/cat.png")
  assert !artifacts.viewable("/notes.txt")
}
