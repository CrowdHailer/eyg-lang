//// Prepare an artifact bundle for display in a sandboxed iframe.
////
//// Untrusted markup is never parsed into the application document,
//// `overlay/web/artifact/inline` rewrites it as text.

import gleam/result.{try}
import gleam/string
import overlay/public/puppet
import overlay/web/artifact.{type Bundle}
import overlay/web/artifact/inline

/// Every artifact runs under this policy, set by the wrapper before any artifact content.
/// It can only be restricted further by the artifact.
pub const policy =
  "default-src 'none'; script-src 'unsafe-inline' data:; style-src 'unsafe-inline' data:; img-src data:; font-src data:; media-src data:; connect-src 'none'; frame-src 'none'; worker-src 'none'; object-src 'none'; base-uri 'none'; form-action 'none'"

/// The source of a wrapper frame showing the bundle.
/// A bundle that cannot be prepared shows the reason instead.
pub fn srcdoc(bundle: Bundle) -> String {
  case document(bundle) {
    Ok(html) -> wrapper(html)
    // The puppet is included so an agent can read the reason.
    Error(reason) ->
      wrapper(
        "<!doctype html><html><head><script>"
        <> puppet.script
        <> "</script></head><body><h2>Unable to prepare artifact</h2><pre>"
        <> escape(reason)
        <> "</pre></body></html>",
      )
  }
}

/// A trusted document that fixes the content security policy,
/// then shows `html` in a nested frame with its own opaque origin.
/// The policy of the wrapper also stops the nested frame navigating away.
/// Messages from the application are relayed to the nested frame for the puppet.
pub fn wrapper(html: String) -> String {
  "<!doctype html><html><head><meta charset=\"utf-8\"><meta http-equiv=\"Content-Security-Policy\" content=\""
  <> policy
  <> "\"><meta name=\"referrer\" content=\"no-referrer\"><style>html,body{margin:0;width:100%;height:100%;overflow:hidden}iframe{border:0;width:100%;height:100%;display:block}</style></head><body><iframe title=\"Artifact content\" sandbox=\"allow-scripts\" referrerpolicy=\"no-referrer\" srcdoc=\""
  <> escape(html)
  <> "\"></iframe><script>"
  <> puppet.relay
  <> "</script></body></html>"
}

/// A single HTML document with every file it uses from the bundle inline,
/// and the puppet script that performs requests from the application.
pub fn document(bundle: Bundle) -> Result(String, String) {
  use entry <- try(
    artifact.file(bundle, "index.html")
    |> result.replace_error("Missing index.html"),
  )
  use source <- try(inline.text(entry))
  use html <- try(inline.document(bundle, source, entry.path))
  // The puppet runs before any artifact script.
  Ok("<!doctype html><script>" <> puppet.script <> "</script>" <> html)
}

fn escape(text) {
  text
  |> string.replace("&", "&amp;")
  |> string.replace("\"", "&quot;")
  |> string.replace("<", "&lt;")
  |> string.replace(">", "&gt;")
}
