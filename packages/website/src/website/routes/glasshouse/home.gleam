//// Glasshouse records portable trajectories and replays them without host effects.

import lustre/attribute as a
import lustre/element
import lustre/element/html as h
import mysig/asset
import website/components
import website/routes/glasshouse/layout

pub fn page() {
  use content <- asset.do(
    layout.page(
      "/glasshouse",
      "Glasshouse: recorded EYG trajectories",
      "Save pinned EYG code, effect journals and model context in a portable archive. Inspect and replay it in the browser or CLI.",
      [],
      [
        components.header(),
        layout.nav("/glasshouse"),
        h.main([a.class("gh-section")], [
          h.h1([a.class("gh-section-title")], [h.text("Glasshouse")]),
          h.p([a.class("gh-hero-lead")], [
            h.text(
              "Record EYG trajectories. Keep the code, requests and replies together, then inspect and reproduce each execution offline.",
            ),
          ]),
          h.div([a.class("gh-actions")], [
            h.a(
              [
                a.class("gh-action gh-action-primary"),
                a.href("/glasshouse/debugger"),
              ],
              [h.text("Open the debugger")],
            ),
            h.a([a.class("gh-action"), a.href("/glasshouse/documentation")], [
              h.text("Read the guide"),
            ]),
          ]),
          h.h2([a.class("mt-8")], [h.text("Record locally or in Overlay")]),
          h.pre([a.class("gh-pre")], [
            h.text(
              "eyg record run -c 'perform StandardOut(\"hello\\n\")'\neyg inspect .eyg/traces/<session>.json\neyg replay .eyg/traces/<session>.json",
            ),
          ]),
          h.p([], [
            h.text(
              "Overlay keeps prompts, model generations, tool calls and effect journals in the Trace panel. Download the archive and open it in the debugger.",
            ),
          ]),
          h.h2([a.class("mt-8")], [h.text("Pinned code and observed state")]),
          h.p([], [
            h.text(
              "Archives contain content-addressed values, a module lock and ordered effects. Replay checks the original requests and supplies recorded replies. Unobserved files and services are outside a host recording.",
            ),
          ]),
          h.h2([a.class("mt-8")], [h.text("Inspect every moment")]),
          h.p([], [
            h.text(
              "Step through prompts, generations, tool results and effects. See model context, observed files and write diffs. Load several archives to compare their outcomes and token use.",
            ),
          ]),
          h.h2([a.class("mt-8")], [h.text("Export standard telemetry")]),
          h.p([], [
            h.text(
              "Upload OTLP spans to Jaeger or Langfuse. Spans carry model and tool summaries and references into the archive; the archive remains the replay evidence.",
            ),
          ]),
          h.pre([a.class("gh-pre")], [
            h.text(
              "OTEL_EXPORTER_OTLP_ENDPOINT=http://localhost:4318 eyg upload .eyg/traces/<session>.json",
            ),
          ]),
        ]),
        components.footer(),
      ],
    ),
  )
  asset.done(element.to_document_string(content))
}
