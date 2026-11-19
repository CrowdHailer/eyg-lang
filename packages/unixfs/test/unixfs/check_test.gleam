import eyg/hub/cache
import gleam/dict
import gleam/list
import gleam/option.{type Option, Some}
import multiformats/cid/v1
import unixfs/check
import unixfs/mfs

// Run effects against blocks in memory, counting the blocks that are read.
fn run(effect, blocks, reads) {
  case effect {
    mfs.Done(value) -> #(value, blocks, reads)
    mfs.Get(cid, resume) -> {
      let assert Ok(entry) = list.key_find(blocks, cid)
      run(resume(entry), blocks, [cid, ..reads])
    }
    mfs.Put(entry, resume) -> {
      let stored = mfs.identify(entry)
      run(resume(stored), [#(stored.cid, entry), ..blocks], reads)
    }
  }
}

// The root of a file system with the files, stored in the blocks.
fn files(files: List(#(List(String), String)), blocks) {
  let effect = write(files, Some(mfs.Directory([])))
  let #(root, blocks, _) = run(effect, blocks, [])
  #(root, blocks)
}

fn write(files, root: Option(mfs.Entry)) {
  case files {
    [] -> {
      let assert Some(root) = root
      use _ <- mfs.Put(root)
      mfs.Done(root)
    }
    [#(path, contents), ..files] -> {
      let root = case list.reverse(path) {
        [_, ..parent] if parent != [] -> {
          use root <- mfs.then(mfs.make_directory_all(
            root,
            list.reverse(parent),
          ))
          let assert Ok(root) = root
          mfs.Done(Some(root))
        }
        _ -> mfs.Done(root)
      }
      use root <- mfs.then(root)
      use root <- mfs.then(mfs.write(root, path, <<contents:utf8>>))
      let assert Ok(root) = root
      write(files, Some(root))
    }
  }
}

const library = [
  #(["lib", "one.eyg"], "1"),
  #(["lib", "two.eyg"], "!int_add(import \"./one.eyg\", 1)"),
  #(["app", "main.eyg"], "!int_add(import \"../lib/two.eyg\", 1)"),
  #(["other.eyg"], "\"other\""),
  #(["notes.txt"], "notes"),
]

// Check the library, then the files after a change from its index,
// the outcome is the same as checking the files after the change in full.
fn check_change(after: List(#(List(String), String))) {
  let #(before, blocks) = files(library, [])
  let #(#(_, index), blocks, _) =
    run(check.index(before, cache.ready()), blocks, [])
  let #(after, blocks) = files(after, blocks)
  let #(#(changed, _), _, reads) =
    run(check.change(index, after, cache.ready()), blocks, [])
  let #(full, _, _) = run(check.entry(after, cache.ready()), blocks, [])
  assert changed == full
  #(changed, reads, blocks)
}

fn replace(files, path, contents) {
  list.key_set(files, path, contents)
}

pub fn index_is_the_same_as_a_full_check_test() {
  let #(root, blocks) = files(library, [])
  let #(#(indexed, _), _, _) = run(check.index(root, cache.ready()), blocks, [])
  let #(full, _, _) = run(check.entry(root, cache.ready()), blocks, [])
  assert indexed == full
  assert 4 == dict.size(full)
}

pub fn change_a_module_test() {
  let #(checked, _, _) = check_change(replace(library, ["lib", "one.eyg"], "2"))
  assert list.all(dict.values(checked), fn(outcome) {
    outcome != Error(check.MissingModule)
  })
}

pub fn changed_type_breaks_unchanged_importer_test() {
  let #(checked, _, _) =
    check_change(replace(library, ["lib", "one.eyg"], "\"one\""))
  let assert Ok(Error(check.TypeErrors(_))) =
    dict.get(checked, ["lib", "two.eyg"])
}

pub fn remove_a_module_test() {
  let #(checked, _, _) =
    check_change(
      list.filter(library, fn(file) { file.0 != ["lib", "one.eyg"] }),
    )
  assert Ok(Error(check.MissingModule)) == dict.get(checked, ["lib", "one.eyg"])
}

pub fn add_a_module_test() {
  check_change(list.append(library, [#(["new.eyg"], "import \"./other.eyg\"")]))
}

pub fn import_a_file_that_is_not_a_module_test() {
  check_change(replace(library, ["other.eyg"], "import \"./notes.txt\""))
}

pub fn stop_importing_a_file_that_is_not_a_module_test() {
  let library =
    replace(library, ["other.eyg"], "let _ = import \"./data.json\"\n1")
    |> list.append([#(["data.json"], "{}")])
  let #(before, blocks) = files(library, [])
  let #(#(_, index), blocks, _) =
    run(check.index(before, cache.ready()), blocks, [])
  let #(after, blocks) = files(replace(library, ["other.eyg"], "1"), blocks)
  let #(#(changed, _), _, _) =
    run(check.change(index, after, cache.ready()), blocks, [])
  let #(full, _, _) = run(check.entry(after, cache.ready()), blocks, [])
  assert changed == full
  assert Error(Nil) == dict.get(changed, ["data.json"])
}

pub fn modules_that_did_not_change_are_not_read_test() {
  let other = mfs.identify(mfs.File(<<"\"other\"":utf8>>)).cid
  let one = mfs.identify(mfs.File(<<"1":utf8>>)).cid
  let #(_, reads, _) =
    check_change(replace(library, ["notes.txt"], "more notes"))
  let read = fn(cid: v1.Cid) { list.contains(reads, cid) }
  assert !read(other) && !read(one)
  let #(_, reads, _) = check_change(replace(library, ["lib", "one.eyg"], "2"))
  assert !list.contains(reads, other)
}

pub fn a_single_file_test() {
  let file = mfs.File(<<"!int_add(1, 2)":utf8>>)
  let #(#(indexed, index), blocks, _) =
    run(
      {
        use _ <- mfs.Put(file)
        check.index(file, cache.ready())
      },
      [],
      [],
    )
  let assert [#([], Ok(_))] = dict.to_list(indexed)
  let changed = mfs.File(<<"\"two\"":utf8>>)
  let #(#(checked, _), _, _) =
    run(
      {
        use _ <- mfs.Put(changed)
        check.change(index, changed, cache.ready())
      },
      blocks,
      [],
    )
  let #(full, _, _) = run(check.entry(changed, cache.ready()), blocks, [])
  assert checked == full
}
