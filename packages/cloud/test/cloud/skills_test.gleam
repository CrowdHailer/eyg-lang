import cloud/beam/execute
import cloud/files
import cloud/skills
import gleam/dict
import gleam/option.{Some}
import gleam/string

pub fn frontmatter_test() {
  let text = "---\nname: greet\ndescription: Greet people.\n---\nbody"
  assert skills.frontmatter(text, "dir") == #("greet", "Greet people.")
}

pub fn missing_frontmatter_test() {
  assert skills.frontmatter("just text", "dir") == #("dir", "")
}

pub fn index_test() {
  let assert Ok(fs) = files.seed(Some("test/fixtures/files"), dict.new())
  let index = skills.index(execute.session_files(fs))
  assert index
    == [
      skills.Skill("greet", "Greet people by name.", "/skills/greet/SKILL.md"),
    ]
  assert string.contains(
    skills.render(index),
    "- greet (`/skills/greet/SKILL.md`)",
  )
}
