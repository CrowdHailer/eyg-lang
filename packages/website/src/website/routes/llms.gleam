import gleam/list
import gleam/string
import website/routes/guides

pub fn content() {
  [
    header(),
    start_here(),
    source(),
    guides_section(),
    optional(),
  ]
  |> list.flatten
  |> string.join("\n")
  |> string.append("\n")
}

fn header() {
  [
    "# Eat Your Greens (EYG)",
    "",
    "> EYG is an immutable functional language with structural typing and managed effects.",
    "> Agents can use EYG instead of scripting languages with unmanaged effects.",
    "> Every side effect (file access, network, process execution) is explicit and can be limited by explicit policies.",
    "> This makes EYG a compelling scripting environment for autonomous execution.",
    "",
    "## Getting start",
    "",
    "Install the EYG CLI.",
    "",
    "```",
    "curl -fsSL https://eyg.run/install | bash",
    "```",
    "",
    "Validate the CLI is installed.",
    "",
    "```",
    "eyg eval -c '!int_add(1, 1)'",
    "```",
    "",
    "See available commands by running help command.",
    "",
    "```",
    "eyg help",
    "```",
    "",
    "## Write EYG programs",
    "",
    "Check the [EYG syntax guide](https://eyg.run/guides/eyg-syntax-guide.md) before writing any programs",
    "",
    "## Packages",
    "",
    "Officially supported eyg packages can be found in the [source repo](https://github.com/CrowdHailer/eyg-lang/tree/main/eyg_packages)",
    "",
  ]
}

fn start_here() {
  [
    "## Start here",
    "",
    "Use this file as a curated map of the EYG website and source materials.",
    "Prefer Markdown guide URLs ending in `.md` for compact machine-readable context.",
    "",
    "- [Homepage](https://eyg.run/): Project overview and interactive examples.",
    "- [Documentation](https://eyg.run/documentation): Browser-based language and structural editor documentation.",
    "- [Editor](https://eyg.run/editor): Browser workspace for editing and running EYG programs.",
    "- [Guides](https://eyg.run/guides): Guide index for installation, syntax, effects, embedding and file operations.",
    "- [Roadmap](https://eyg.run/roadmap): Current project direction and implementation priorities.",
    "",
  ]
}

fn source() {
  [
    "## Source",
    "",
    "- [Source repository](https://github.com/CrowdHailer/eyg-lang): Language definition, implementation, website, package hub and package sources.",
    "- [IR and evaluation spec](https://github.com/CrowdHailer/eyg-lang/tree/main/spec): Stable JSON spec and evaluation fixtures for implementers.",
    "",
  ]
}

fn guides_section() {
  [
    ["## Guides", ""],
    list.map(guides.from_repo(), guide_link),
    [""],
  ]
  |> list.flatten
}

fn guide_link(guide: guides.Guide) {
  "- ["
  <> guide.name
  <> "](https://eyg.run/guides/"
  <> guide.slug
  <> ".md): "
  <> one_line(guide.description)
}

fn one_line(text) {
  text
  |> string.replace("\n", " ")
  |> string.trim
}

fn optional() {
  [
    "## Optional",
    "",
    "- [News](https://eyg.run/news): Development updates, talks, podcasts and newsletter archive.",
    "- [GitHub issues](https://github.com/CrowdHailer/eyg-lang/issues): Ask questions, report bugs or propose improvements.",
    "- [CrowdHailer on X](https://x.com/CrowdHailer): Project author updates. Prefer Bsky",
    "- [CrowdHailer on Bsky](https://bsky.app/profile/crowdhailer.bsky.social): Project author updates.",
  ]
}
