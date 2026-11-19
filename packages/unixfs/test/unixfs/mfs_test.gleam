import gleam/list
import gleam/option
import gleam/string
import simplifile
import unixfs/mfs

// Run effects against blocks in memory.
fn run(effect, blocks) {
  case effect {
    mfs.Done(value) -> #(Ok(value), blocks)
    mfs.Get(cid, resume) ->
      case list.key_find(blocks, cid) {
        Ok(entry) -> run(resume(entry), blocks)
        Error(Nil) -> #(Error(simplifile.Enoent), blocks)
      }
    mfs.Put(entry, resume) -> {
      let stored = mfs.identify(entry)
      run(resume(stored), [#(stored.cid, entry), ..blocks])
    }
  }
}

pub fn then_with_plain_values_test() {
  let effect = {
    use value <- mfs.then(mfs.Done(41))
    mfs.Done(value + 1)
  }
  assert #(Ok(42), []) == run(effect, [])
}

pub fn then_can_recover_from_missing_path_test() {
  let empty = mfs.Directory([])
  let root = mfs.identify(empty).cid
  let fallback = mfs.File(<<"fallback">>)
  let effect = {
    use outcome <- mfs.then(mfs.read(root, ["file.txt"]))
    assert Error(simplifile.Enoent) == outcome
    use stored <- mfs.then(mfs.Put(fallback, mfs.Done))
    use entry <- mfs.then(mfs.Get(stored.cid, mfs.Done))
    mfs.Done(entry == fallback)
  }
  let assert #(Ok(True), [_, _]) = run(effect, [#(root, empty)])
}

pub fn missing_block_stops_runner_test() {
  let missing = mfs.identify(mfs.Directory([])).cid
  let effect = {
    use _ <- mfs.then(mfs.read(missing, ["file.txt"]))
    panic as "A missing block must not resume the computation"
  }
  let assert #(Error(simplifile.Enoent), []) = run(effect, [])
}

pub fn try_stops_before_writing_after_failure_test() {
  let effect = {
    use entry <- mfs.then(mfs.write(option.None, ["missing", "file.txt"], <<>>))
    use entry <- mfs.try(entry)
    use stored <- mfs.Put(entry)
    mfs.Done(Ok(stored))
  }
  let assert #(Ok(Error(simplifile.Enoent)), []) = run(effect, [])
}

/// Write all files into the tree. Could become public API.
fn tree(files: List(#(List(String), String)), blocks) {
  let effect =
    list.fold(files, mfs.Done(Ok(mfs.Directory([]))), fn(effect, file) {
      let #(path, contents) = file
      use entry <- mfs.then(effect)
      use entry <- mfs.try(entry)
      use entry <- mfs.then(mfs.make_directory_all(
        option.Some(entry),
        list.take(path, list.length(path) - 1),
      ))
      use entry <- mfs.try(entry)
      mfs.write(option.Some(entry), path, <<contents:utf8>>)
    })
  let effect = {
    use entry <- mfs.then(effect)
    use entry <- mfs.try(entry)
    use stored <- mfs.Put(entry)
    mfs.Done(Ok(stored))
  }
  let assert #(Ok(Ok(stored)), blocks) = run(effect, blocks)
  #(stored.cid, blocks)
}

pub fn diff_test() {
  let #(old, blocks) =
    tree(
      [
        #(["a.txt"], "a"),
        #(["lib", "b.txt"], "b"),
        #(["lib", "c.txt"], "c"),
        #(["same", "d.txt"], "d"),
      ],
      [],
    )
  let #(new, blocks) =
    tree(
      [
        #(["a.txt"], "changed"),
        #(["lib", "b.txt"], "b"),
        #(["new.txt"], "n"),
        #(["same", "d.txt"], "d"),
      ],
      blocks,
    )
  let assert #(Ok(paths), _) = run(mfs.diff(old, new), blocks)
  assert [["a.txt"], ["lib", "c.txt"], ["new.txt"]]
    == list.sort(paths, fn(a, b) {
      string.compare(string.join(a, "/"), string.join(b, "/"))
    })
  let assert #(Ok([]), _) = run(mfs.diff(old, old), blocks)
}

pub fn diff_file_and_directory_test() {
  let #(old, blocks) = tree([#(["x"], "file")], [])
  let #(new, blocks) = tree([#(["x", "y.txt"], "y")], blocks)
  let assert #(Ok(paths), _) = run(mfs.diff(old, new), blocks)
  assert [["x"], ["x", "y.txt"]]
    == list.sort(paths, fn(a, b) {
      string.compare(string.join(a, "/"), string.join(b, "/"))
    })
}

pub fn unchanged_directories_are_not_read_test() {
  let #(old, blocks) = tree([#(["same", "d.txt"], "d"), #(["a.txt"], "a")], [])
  let #(new, blocks) =
    tree([#(["same", "d.txt"], "d"), #(["a.txt"], "b")], blocks)
  let assert #(Ok(Ok(same)), _) = run(mfs.read_directory(old, []), blocks)
  let assert Ok(same) = list.find(same, fn(link) { link.name == "same" })
  // Without the blocks inside the unchanged directory the diff still works.
  let blocks = list.filter(blocks, fn(block) { block.0 != same.cid })
  let assert #(Ok([["a.txt"]]), _) = run(mfs.diff(old, new), blocks)
}
