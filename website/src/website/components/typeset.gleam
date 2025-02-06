// scrawl article post essay

import jot

pub fn text(content) {
  jot.Text(content <> " ")
}

pub fn emphasis(content) {
  jot.Emphasis([jot.Text(content)])
}

pub fn strong(content) {
  jot.Strong([jot.Text(content)])
}

pub fn code(content) {
  jot.Code(content)
}
