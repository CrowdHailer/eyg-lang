import gleam/list
import midas/task as t

fn build_drafting() {
  use script <- t.do(t.bundle("drafting/app", "run"))
  let files = [#("/drafting.js", <<script:utf8>>)]
  use index <- t.do(t.read("src/drafting/index.html"))
  t.done([#("/drafting/index.html", index), ..files])
}

fn build_examine() {
  use script <- t.do(t.bundle("examine/app", "run"))
  let files = [#("/examine.js", <<script:utf8>>)]
  use index <- t.do(t.read("src/examine/index.html"))
  t.done([#("/examine/index.html", index), ..files])
}

fn build_spotless() {
  use script <- t.do(t.bundle("spotless/app", "run"))
  let files = [#("/spotless.js", <<script:utf8>>)]
  use index <- t.do(t.read("src/spotless/index.html"))
  use prompt <- t.do(t.read("saved/prompt.json"))

  t.done([#("/terminal/index.html", index), #("/prompt.json", prompt), ..files])
}

pub fn preview() {
  use drafting <- t.do(build_drafting())
  use examine <- t.do(build_examine())
  use spotless <- t.do(build_spotless())

  let files = list.flatten([drafting, examine, spotless])
  t.done(files)
}
