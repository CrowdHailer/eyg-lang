//// Skills in the workspace's file system.
////
//// A skill is a file `/skills/<dir>/SKILL.md` with the same frontmatter as overlay skills:
////
//// ```md
//// ---
//// name: summarise
//// description: How to summarise web pages.
//// ---
//// body...
//// ```
////
//// Agents are given an index of skills and read a skill's file when it is relevant.

import cloud/beam/execute
import gleam/bit_array
import gleam/list
import gleam/result
import gleam/string
import touch_grass/file_system/read_directory

pub const root = "/skills"

pub type Skill {
  Skill(name: String, description: String, path: String)
}

/// Every skill in the file system.
pub fn index(files: execute.Files) -> List(Skill) {
  case files.read_directory(root) {
    Error(_) -> []
    Ok(entries) ->
      list.filter_map(entries, fn(entry) {
        case entry {
          #(directory, read_directory.Directory) -> {
            let path = root <> "/" <> directory <> "/SKILL.md"
            use bytes <- result.try(
              files.read(path) |> result.replace_error(Nil),
            )
            use text <- result.try(bit_array.to_string(bytes))
            let #(name, description) = frontmatter(text, directory)
            Ok(Skill(name:, description:, path:))
          }
          _ -> Error(Nil)
        }
      })
  }
}

/// The name and description from a skill's frontmatter, without frontmatter the fallback name is used.
pub fn frontmatter(text: String, fallback: String) -> #(String, String) {
  let fields = case string.split_once(text, "---\n") {
    Ok(#("", rest)) ->
      case string.split_once(rest, "\n---") {
        Ok(#(frontmatter, _body)) ->
          string.split(frontmatter, "\n")
          |> list.filter_map(fn(line) {
            string.split_once(line, ": ")
            |> result.map(fn(pair) { #(pair.0, string.trim(pair.1)) })
          })
        Error(Nil) -> []
      }
    _ -> []
  }
  #(
    list.key_find(fields, "name") |> result.unwrap(fallback),
    list.key_find(fields, "description") |> result.unwrap(""),
  )
}

/// A section for the agent's context listing the skills.
pub fn render(skills: List(Skill)) -> String {
  case skills {
    [] -> ""
    _ -> "## Skills

Skills are instructions for specific tasks, read a skill's file with the `ReadFile` effect before doing the task.

" <> {
        skills
        |> list.map(fn(skill) {
          "- "
          <> skill.name
          <> " (`"
          <> skill.path
          <> "`): "
          <> skill.description
        })
        |> string.join("\n")
      }
  }
}
