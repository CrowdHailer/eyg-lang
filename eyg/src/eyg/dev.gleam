import midas/task as t

pub fn preview() {
  use script <- t.do(t.bundle("drafting/app", "run"))
  let files = [#("/drafting.js", <<script:utf8>>)]
  use index <- t.do(t.read("src/drafting/index.html"))
  //   let src_name = ""
  let files = [#("/drafting/index.html", index), ..files]
  t.done(files)
}
