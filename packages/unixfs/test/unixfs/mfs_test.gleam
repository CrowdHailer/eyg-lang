import gleam/list
import gleam/option
import gleam/result
import gleam/string
import simplifile
import unixfs/mfs

// Run effects against blocks in memory.
fn run(effect, blocks) {
  case effect {
    mfs.Done(value) -> #(value, blocks)
    mfs.Get(cid, resume) ->
      run(
        resume(
          list.key_find(blocks, cid) |> result.replace_error(simplifile.Enoent),
        ),
        blocks,
      )
    mfs.Put(entry, resume) -> {
      let stored = mfs.identify(entry)
      run(resume(Ok(stored)), [#(stored.cid, entry), ..blocks])
    }
  }
}

/// Write all files into the tree. Could become public API.
fn tree(files: List(#(List(String), String)), blocks) {
  let effect =
    list.fold(files, mfs.Done(Ok(mfs.Directory([]))), fn(effect, file) {
      let #(path, contents) = file
      use entry <- mfs.then(effect)
      use entry <- mfs.then(mfs.make_directory_all(
        option.Some(entry),
        list.take(path, list.length(path) - 1),
      ))
      mfs.write(option.Some(entry), path, <<contents:utf8>>)
    })
  let effect = {
    use entry <- mfs.then(effect)
    mfs.Put(entry, mfs.Done)
  }
  let assert #(Ok(stored), blocks) = run(effect, blocks)
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
  let assert #(Ok(same), _) = run(mfs.read_directory(old, []), blocks)
  let assert Ok(same) = list.find(same, fn(link) { link.name == "same" })
  // Without the blocks inside the unchanged directory the diff still works.
  let blocks = list.filter(blocks, fn(block) { block.0 != same.cid })
  let assert #(Ok([["a.txt"]]), _) = run(mfs.diff(old, new), blocks)
}
