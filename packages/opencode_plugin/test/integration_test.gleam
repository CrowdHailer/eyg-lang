import opencode_plugin/integration

pub fn installer_refuses_different_or_tampered_source_test() {
  let assert Error(_) = integration.patch("return tools")
  let assert Error(_) =
    integration.patch(
      "import * as Eyg from \"@/tool/eyg/dispatch.mjs\"\nreturn yield* eygTools()",
    )
  assert integration.digest("abc")
    == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
}
