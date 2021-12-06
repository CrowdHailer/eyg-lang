import gleam/list

pub fn root() {
  []
}

pub fn append(path, i) {
  list.append(path, [i])
}
