import eyg/analysis/type_/isomorphic as t
import eyg/hub/cache
import eyg/hub/publisher
import eyg/hub/schema
import eyg/interpreter/break
import eyg/interpreter/value as v
import eyg/ir/cid
import eyg/ir/tree as ir
import gleam/bit_array
import gleam/crypto
import gleam/dict
import gleam/int
import gleam/list
import gleam/option.{None}
import untethered/substrate

pub fn empty_cache_has_no_effects_test() {
  let cache = cache.empty()
  assert #(cache, []) == cache.flush(cache)
}

pub fn pull_idempotency_test() {
  let cache = cache.pull(cache.empty())

  // if lined up already pulling makes no change
  assert cache == cache.pull(cache)

  let assert #(cache, [effect]) = cache.flush(cache)
  assert cache.PullPackages(0) == effect

  // effect is only returned once
  assert #(cache, []) == cache.flush(cache)
  assert cache == cache.pull(cache)
}

pub fn fetch_idemotency_test() {
  let #(cid, _) = random_code()
  let cache = cache.fetch(cache.empty(), cid)

  // if lined up already fetching makes no change
  assert cache == cache.fetch(cache, cid)

  let assert #(cache, [effect]) = cache.flush(cache)
  assert cache.FetchModule(cid) == effect

  // effect is only returned once
  assert #(cache, []) == cache.flush(cache)
  assert cache == cache.fetch(cache, cid)
}

pub fn successful_fetch_test() {
  let num = int.random(1_000_000)
  let #(cid, source) = code(num)
  let cache = cache.fetch(cache.empty(), cid)
  assert cache.Unknown == cache.module(cache, cid)

  let assert #(cache, [effect]) = cache.flush(cache)
  assert cache.FetchModule(cid) == effect

  let #(cache, done) = cache.fetch_module_completed(cache, cid, Ok(source))
  assert [#(cid, Ok(v.Integer(num)))] == done
  let assert cache.Available(module) = cache.module(cache, cid)
  assert cache.Module(v.Integer(num), t.Integer) == module

  assert Error(Nil) == dict.get(cache.fetching_modules, cid)
  assert cache == cache.fetch(cache, cid)
}

pub fn fetch_dependent_references_test() {
  let num = int.random(1_000_000)
  let #(child_cid, child) = code(num)

  let parent =
    ir.add(ir.reference(child_cid), ir.integer(1))
    |> ir.map_annotation(fn(_) { [] })
  let parent_cid = cid_from_tree(parent)

  let cache = cache.fetch(cache.empty(), parent_cid)

  let assert #(cache, [effect]) = cache.flush(cache)
  assert cache.FetchModule(parent_cid) == effect
  let #(cache, done) =
    cache.fetch_module_completed(cache, parent_cid, Ok(parent))
  let assert Ok(cache.DependsOn(dep:, ..)) =
    dict.get(cache.fetching_modules, parent_cid)
  assert ir.Content(child_cid) == dep
  assert [] == done

  let assert #(cache, [effect]) = cache.flush(cache)
  assert cache.FetchModule(child_cid) == effect
  let #(cache, done) = cache.fetch_module_completed(cache, child_cid, Ok(child))
  assert [
      #(parent_cid, Ok(v.Integer(num + 1))),
      #(child_cid, Ok(v.Integer(num))),
    ]
    == done
  let assert cache.Available(module) = cache.module(cache, parent_cid)
  assert cache.Module(v.Integer(num + 1), t.Integer) == module
  let assert cache.Available(module) = cache.module(cache, child_cid)
  assert cache.Module(v.Integer(num), t.Integer) == module
  assert dict.new() == cache.fetching_modules
}

pub fn already_available_reference_test() {
  let num = int.random(1_000_000)
  let #(child_cid, child) = code(num)

  let parent =
    ir.add(ir.reference(child_cid), ir.integer(1))
    |> ir.map_annotation(fn(_) { [] })
  let parent_cid = cid_from_tree(parent)

  let cache = cache.empty()
  let #(cache, done) = cache.fetch_module_completed(cache, child_cid, Ok(child))
  assert [#(child_cid, Ok(v.Integer(num)))] == done

  let assert cache.Available(module) = cache.module(cache, child_cid)
  assert v.Integer(num) == module.value

  let #(cache, done) =
    cache.fetch_module_completed(cache, parent_cid, Ok(parent))
  assert Error(Nil) == dict.get(cache.fetching_modules, parent_cid)
  assert [#(parent_cid, Ok(v.Integer(num + 1)))] == done
}

pub fn fetch_failure_will_retry_test() {
  let num = int.random(1_000_000)
  let #(cid, _source) = code(num)
  let cache = cache.fetch(cache.empty(), cid)
  assert cache.Unknown == cache.module(cache, cid)

  let assert #(cache, [effect]) = cache.flush(cache)
  assert cache.FetchModule(cid) == effect

  let #(cache, done) =
    cache.fetch_module_completed(cache, cid, Error("test error"))
  assert [] == done
  assert cache.Unknown == cache.module(cache, cid)
}

pub fn invalid_reference_wont_be_refetched_test() {
  let source =
    ir.vacant()
    |> ir.map_annotation(fn(_) { [] })
  let cid = cid_from_tree(source)
  let cache = cache.empty()
  let #(cache, done) = cache.fetch_module_completed(cache, cid, Ok(source))
  assert [#(cid, Error(break.Vacant))] == done
  assert cache == cache.fetch(cache, cid)
  assert #(cache, []) == cache.flush(cache)
}

pub fn fetch_dependent_invalid_references_test() {
  let child =
    ir.call(ir.perform("Zing"), [ir.unit()])
    |> ir.map_annotation(fn(_) { [] })
  let child_cid = cid_from_tree(child)

  let parent =
    ir.add(ir.reference(child_cid), ir.integer(1))
    |> ir.map_annotation(fn(_) { [] })
  let parent_cid = cid_from_tree(parent)

  let cache = cache.empty()

  let #(cache, done) =
    cache.fetch_module_completed(cache, parent_cid, Ok(parent))
  let assert Ok(cache.DependsOn(dep:, ..)) =
    dict.get(cache.fetching_modules, parent_cid)
  assert ir.Content(child_cid) == dep
  assert [] == done

  let assert #(cache, [effect]) = cache.flush(cache)
  assert cache.FetchModule(child_cid) == effect
  let #(cache, done) = cache.fetch_module_completed(cache, child_cid, Ok(child))

  let reason = break.UnhandledEffect("Zing", v.unit())
  assert [#(parent_cid, Error(reason)), #(child_cid, Error(reason))] == done
  assert cache.Unavailable(reason) == cache.module(cache, parent_cid)
  assert cache.Unavailable(reason) == cache.module(cache, child_cid)
}

pub fn already_invalid_reference_cascades_to_parent_test() {
  let child =
    ir.call(ir.perform("Zing"), [ir.unit()])
    |> ir.map_annotation(fn(_) { [] })
  let child_cid = cid_from_tree(child)

  let parent =
    ir.add(ir.reference(child_cid), ir.integer(1))
    |> ir.map_annotation(fn(_) { [] })
  let parent_cid = cid_from_tree(parent)

  let cache = cache.empty()
  let #(cache, done) = cache.fetch_module_completed(cache, child_cid, Ok(child))
  let reason = break.UnhandledEffect("Zing", v.unit())
  assert [#(child_cid, Error(reason))] == done
  assert cache.Unavailable(reason) == cache.module(cache, child_cid)

  let #(cache, done) =
    cache.fetch_module_completed(cache, parent_cid, Ok(parent))
  assert Ok(cache.Invalid(reason))
    == dict.get(cache.fetching_modules, parent_cid)
  assert [#(parent_cid, Error(break.UnhandledEffect("Zing", v.unit())))] == done
}

pub fn failure_after_resumption_marks_module_as_invalid_test() {
  let num = int.random(1_000_000)
  let #(child_cid, child) = code(num)

  let parent =
    ir.add(ir.reference(child_cid), ir.string("not a number"))
    |> ir.map_annotation(fn(_) { [] })
  let parent_cid = cid_from_tree(parent)

  let cache = cache.empty()
  let #(cache, done) =
    cache.fetch_module_completed(cache, parent_cid, Ok(parent))
  assert [] == done

  let #(cache, done) = cache.fetch_module_completed(cache, child_cid, Ok(child))

  let reason = break.IncorrectTerm("Integer", v.String("not a number"))
  assert cache.Unavailable(reason) == cache.module(cache, parent_cid)
  assert cache.Available(cache.Module(v.Integer(num), t.Integer))
    == cache.module(cache, child_cid)
  assert [#(parent_cid, Error(reason)), #(child_cid, Ok(v.Integer(num)))]
    == done
}

pub fn will_resolve_references_after_resumption_test() {
  let num = int.random(1_000_000)
  let #(child_cid, child) = code(num)

  let parent =
    ir.add(ir.reference(child_cid), ir.reference(child_cid))
    |> ir.map_annotation(fn(_) { [] })
  let parent_cid = cid_from_tree(parent)

  let cache = cache.empty()
  let #(cache, done) =
    cache.fetch_module_completed(cache, parent_cid, Ok(parent))
  assert [] == done

  let #(cache, done) = cache.fetch_module_completed(cache, child_cid, Ok(child))

  assert cache.Available(cache.Module(v.Integer(num + num), t.Integer))
    == cache.module(cache, parent_cid)
  assert cache.Available(cache.Module(v.Integer(num), t.Integer))
    == cache.module(cache, child_cid)
  assert [
      #(parent_cid, Ok(v.Integer(num + num))),
      #(child_cid, Ok(v.Integer(num))),
    ]
    == done
}

pub fn will_lookup_multiple_reference_test() {
  let num1 = int.random(1_000_000)
  let #(child_cid1, child1) = code(num1)
  let num2 = int.random(1_000_000)
  let #(child_cid2, child2) = code(num2)

  let parent =
    ir.add(ir.reference(child_cid1), ir.reference(child_cid2))
    |> ir.map_annotation(fn(_) { [] })
  let parent_cid = cid_from_tree(parent)

  let cache = cache.empty()
  let #(cache, done) =
    cache.fetch_module_completed(cache, parent_cid, Ok(parent))
  assert [] == done

  let #(cache, done) =
    cache.fetch_module_completed(cache, child_cid1, Ok(child1))
  assert [#(child_cid1, Ok(v.Integer(num1)))] == done
  assert cache.Available(cache.Module(v.Integer(num1), t.Integer))
    == cache.module(cache, child_cid1)
  assert cache.Unknown == cache.module(cache, parent_cid)

  let #(cache, effects) = cache.flush(cache)
  assert [cache.FetchModule(child_cid2)] == effects

  let #(cache, done) =
    cache.fetch_module_completed(cache, child_cid2, Ok(child2))
  assert [
      #(parent_cid, Ok(v.Integer(num1 + num2))),
      #(child_cid2, Ok(v.Integer(num2))),
    ]
    == done
  assert cache.Available(cache.Module(v.Integer(num2), t.Integer))
    == cache.module(cache, child_cid2)
  assert cache.Available(cache.Module(v.Integer(num1 + num2), t.Integer))
    == cache.module(cache, parent_cid)
}

pub fn multiple_parents_resolve_test() {
  let num = int.random(1_000_000)
  let #(child_cid, child) = code(num)

  let p1 =
    ir.add(ir.reference(child_cid), ir.integer(10))
    |> ir.map_annotation(fn(_) { [] })
  let p1_cid = cid_from_tree(p1)
  let p2 =
    ir.add(ir.reference(child_cid), ir.integer(20))
    |> ir.map_annotation(fn(_) { [] })
  let p2_cid = cid_from_tree(p2)
  let cache = cache.empty()

  let #(cache, done) = cache.fetch_module_completed(cache, p1_cid, Ok(p1))
  assert [] == done
  let #(cache, done) = cache.fetch_module_completed(cache, p2_cid, Ok(p2))
  assert [] == done
  let #(cache, effects) = cache.flush(cache)
  assert [cache.FetchModule(child_cid)] == effects
  let #(cache, done) = cache.fetch_module_completed(cache, child_cid, Ok(child))

  assert dict.from_list([
      #(p1_cid, Ok(v.Integer(num + 10))),
      #(p2_cid, Ok(v.Integer(num + 20))),
      #(child_cid, Ok(v.Integer(num))),
    ])
    == dict.from_list(done)

  assert dict.new() == cache.fetching_modules
}

pub fn multiple_parents_resolve_failure_test() {
  let child = ir.vacant() |> ir.map_annotation(fn(_) { [] })
  let child_cid = cid_from_tree(child)

  let p1 =
    ir.add(ir.reference(child_cid), ir.integer(10))
    |> ir.map_annotation(fn(_) { [] })
  let p1_cid = cid_from_tree(p1)
  let p2 =
    ir.add(ir.reference(child_cid), ir.integer(20))
    |> ir.map_annotation(fn(_) { [] })
  let p2_cid = cid_from_tree(p2)
  let cache = cache.empty()

  let #(cache, done) = cache.fetch_module_completed(cache, p1_cid, Ok(p1))
  assert [] == done
  let #(cache, done) = cache.fetch_module_completed(cache, p2_cid, Ok(p2))
  assert [] == done
  let #(cache, effects) = cache.flush(cache)
  assert [cache.FetchModule(child_cid)] == effects
  let #(cache, done) = cache.fetch_module_completed(cache, child_cid, Ok(child))

  assert dict.from_list([
      #(p1_cid, Error(break.Vacant)),
      #(p2_cid, Error(break.Vacant)),
      #(child_cid, Error(break.Vacant)),
    ])
    == dict.from_list(done)

  assert cache.Unavailable(break.Vacant) == cache.module(cache, child_cid)
  assert cache.Unavailable(break.Vacant) == cache.module(cache, p1_cid)
  assert cache.Unavailable(break.Vacant) == cache.module(cache, p2_cid)
}

pub fn fetching_a_module_with_invalid_dep_will_cascade_test() {
  let base = ir.vacant() |> ir.map_annotation(fn(_) { [] })
  let base_cid = cid_from_tree(base)
  let cache = cache.empty()
  let #(cache, _) = cache.fetch_module_completed(cache, base_cid, Ok(base))
  assert cache.Unavailable(break.Vacant) == cache.module(cache, base_cid)

  let child = ir.reference(base_cid) |> ir.map_annotation(fn(_) { [] })
  let child_cid = cid_from_tree(child)

  let parent = ir.reference(child_cid) |> ir.map_annotation(fn(_) { [] })
  let parent_cid = cid_from_tree(parent)

  let #(cache, done) =
    cache.fetch_module_completed(cache, parent_cid, Ok(parent))
  assert [] == done
  let #(cache, done) = cache.fetch_module_completed(cache, child_cid, Ok(child))
  assert [#(parent_cid, Error(break.Vacant)), #(child_cid, Error(break.Vacant))]
    == done
  assert cache.Unavailable(break.Vacant) == cache.module(cache, child_cid)
  assert cache.Unavailable(break.Vacant) == cache.module(cache, parent_cid)
}

pub fn resuming_encountering_an_invalid_module_is_invalid_test() {
  let broken = ir.vacant() |> ir.map_annotation(fn(_) { [] })
  let broken_cid = cid_from_tree(broken)
  let cache = cache.empty()
  let #(cache, _) = cache.fetch_module_completed(cache, broken_cid, Ok(broken))
  assert cache.Unavailable(break.Vacant) == cache.module(cache, broken_cid)

  let child = ir.integer(111) |> ir.map_annotation(fn(_) { [] })
  let child_cid = cid_from_tree(child)

  let parent =
    ir.add(ir.reference(child_cid), ir.reference(broken_cid))
    |> ir.map_annotation(fn(_) { [] })
  let parent_cid = cid_from_tree(parent)

  let #(cache, done) =
    cache.fetch_module_completed(cache, parent_cid, Ok(parent))
  assert [] == done
  let #(cache, effects) = cache.flush(cache)
  assert [cache.FetchModule(child_cid)] == effects

  let #(cache, done) = cache.fetch_module_completed(cache, child_cid, Ok(child))
  assert [#(parent_cid, Error(break.Vacant)), #(child_cid, Ok(v.Integer(111)))]
    == done
  assert cache.Available(cache.Module(v.Integer(111), t.Integer))
    == cache.module(cache, child_cid)
  assert cache.Unavailable(break.Vacant) == cache.module(cache, parent_cid)
}

pub fn multiple_parents_failures_after_resumption_test() {
  let num = int.random(1_000_000)
  let #(child_cid, child) = code(num)

  let p1 =
    ir.add(ir.reference(child_cid), ir.string("a"))
    |> ir.map_annotation(fn(_) { [] })
  let p1_cid = cid_from_tree(p1)
  let p2 =
    ir.add(ir.reference(child_cid), ir.string("b"))
    |> ir.map_annotation(fn(_) { [] })
  let p2_cid = cid_from_tree(p2)
  let cache = cache.empty()

  let #(cache, done) = cache.fetch_module_completed(cache, p1_cid, Ok(p1))
  assert [] == done
  let #(cache, done) = cache.fetch_module_completed(cache, p2_cid, Ok(p2))
  assert [] == done
  let #(cache, effects) = cache.flush(cache)
  assert [cache.FetchModule(child_cid)] == effects
  let #(cache, done) = cache.fetch_module_completed(cache, child_cid, Ok(child))

  assert dict.from_list([
      #(p1_cid, Error(break.IncorrectTerm("Integer", v.String("a")))),
      #(p2_cid, Error(break.IncorrectTerm("Integer", v.String("b")))),
      #(child_cid, Ok(v.Integer(num))),
    ])
    == dict.from_list(done)

  assert cache.Available(cache.Module(v.Integer(num), t.Integer))
    == cache.module(cache, child_cid)
  assert cache.Unavailable(break.IncorrectTerm("Integer", v.String("a")))
    == cache.module(cache, p1_cid)
  assert cache.Unavailable(break.IncorrectTerm("Integer", v.String("b")))
    == cache.module(cache, p2_cid)
}

pub fn successfully_pull_release_test() {
  let num = int.random(1_000_000)
  let #(child_cid, child) = code(num)

  let parent =
    ir.add(ir.release("std", 1, child_cid), ir.release("std", 1, child_cid))
    |> ir.map_annotation(fn(_) { [] })
  let parent_cid = cid_from_tree(parent)

  let cache = cache.fetch(cache.empty(), parent_cid)

  let assert #(cache, [effect]) = cache.flush(cache)
  assert cache.FetchModule(parent_cid) == effect
  let #(cache, done) =
    cache.fetch_module_completed(cache, parent_cid, Ok(parent))
  let assert Ok(cache.DependsOn(dep:, ..)) =
    dict.get(cache.fetching_modules, parent_cid)
  assert ir.Pinned(ir.Release("std", 1, child_cid)) == dep
  assert [] == done

  let assert #(cache, [effect]) = cache.flush(cache)

  assert cache.PullPackages(0) == effect
  let release = ir.Release("std", 1, child_cid)
  assert cache.Unknown == cache.release(cache, release)
  let #(cache, done) = cache.pulled(cache, 1, release)
  assert [] == done
  let #(cache, effects) = cache.flush(cache)
  assert [cache.FetchModule(child_cid)] == effects

  let #(cache, done) = cache.fetch_module_completed(cache, child_cid, Ok(child))
  assert [
      #(parent_cid, Ok(v.Integer(num + num))),
      #(child_cid, Ok(v.Integer(num))),
    ]
    == done

  assert cache.Available(child_cid) == cache.release(cache, release)
  assert dict.new() == cache.fetching_modules
  let release = ir.Release("std", 1, child_cid)
  let #(other_cid, _) = random_code()
  let release = ir.Release(..release, module: other_cid)
  assert cache.Unavailable(Nil) == cache.release(cache, release)
}

// pub fn release_less_than_one_is_not_pulled_test() {
//   let #(other_cid, _other) = random_code()
//   let source =
//     ir.release("local", 0, other_cid) |> ir.map_annotation(fn(_) { [] })

//   let return = expression.execute(source, [])
//   let cache = cache.empty()
// TODO test with state on fetched etc
//   // let #(_return, cache) = cache.loop(return, cache, expression.resume)
//   // assert #(cache, []) == cache.flush(cache)
// }

pub fn successful_pull_cascades_test() {
  let num = int.random(1_000_000)
  let #(base_cid, base) = code(num)

  let child = ir.release("bar", 1, base_cid) |> ir.map_annotation(fn(_) { [] })
  let child_cid = cid_from_tree(child)

  let parent =
    ir.add(ir.reference(child_cid), ir.integer(100))
    |> ir.map_annotation(fn(_) { [] })
  let parent_cid = cid_from_tree(parent)

  let bad_parent =
    ir.add(ir.reference(child_cid), ir.vacant())
    |> ir.map_annotation(fn(_) { [] })
  let bad_parent_cid = cid_from_tree(bad_parent)

  // base is already installed as a module
  let cache = cache.empty()
  let #(cache, _effects) =
    cache.fetch_module_completed(cache, base_cid, Ok(base))
  let #(cache, _effects) =
    cache.fetch_module_completed(cache, child_cid, Ok(child))

  let #(cache, done) =
    cache.fetch_module_completed(cache, parent_cid, Ok(parent))
  assert [] == done
  let #(cache, done) =
    cache.fetch_module_completed(cache, bad_parent_cid, Ok(bad_parent))
  assert [] == done
  let #(cache, effects) = cache.flush(cache)
  assert [cache.PullPackages(0)] == effects
  let assert Ok(cache.DependsOn(ir.Pinned(release), ..)) =
    dict.get(cache.fetching_modules, child_cid)
  assert ir.Release("bar", 1, base_cid) == release
  let assert Ok(cache.DependsOn(ir.Content(c), ..)) =
    dict.get(cache.fetching_modules, parent_cid)
  assert child_cid == c
  let #(cache, done) = cache.pulled(cache, 1, ir.Release("bar", 1, base_cid))
  assert dict.from_list([
      #(bad_parent_cid, Error(break.Vacant)),
      #(parent_cid, Ok(v.Integer(num + 100))),
      #(child_cid, Ok(v.Integer(num))),
    ])
    == dict.from_list(done)
  assert dict.from_list([#(bad_parent_cid, cache.Invalid(break.Vacant))])
    == cache.fetching_modules
}

pub fn bad_pull_cascades_test() {
  let num = int.random(1_000_000)
  let #(base_cid, _base) = code(num)
  let #(other_cid, _other) = random_code()

  let child = ir.release("bar", 1, other_cid) |> ir.map_annotation(fn(_) { [] })
  let child_cid = cid_from_tree(child)

  let parent =
    ir.add(ir.reference(child_cid), ir.integer(100))
    |> ir.map_annotation(fn(_) { [] })
  let parent_cid = cid_from_tree(parent)

  let cache = cache.empty()
  let #(cache, _effects) =
    cache.fetch_module_completed(cache, child_cid, Ok(child))

  // parent is in status fetching, it depends on child.
  // When child is invalid this error should cascade.
  let #(cache, done) =
    cache.fetch_module_completed(cache, parent_cid, Ok(parent))
  assert [] == done
  let assert Ok(cache.DependsOn(dep, ..)) =
    dict.get(cache.fetching_modules, parent_cid)
  assert ir.Content(child_cid) == dep

  let assert Ok(cache.DependsOn(ir.Pinned(release), ..)) =
    dict.get(cache.fetching_modules, child_cid)
  assert ir.Release("bar", 1, other_cid) == release

  let #(_cache, done) = cache.pulled(cache, 1, ir.Release("bar", 1, base_cid))

  let done = dict.from_list(done)
  let reason =
    break.UndefinedReference(ir.Pinned(ir.Release("bar", 1, other_cid)))
  assert Ok(Error(reason)) == dict.get(done, child_cid)
  assert Ok(Error(reason)) == dict.get(done, parent_cid)
}

pub fn both_fail_an_invalid_parents_cascade_test() {
  let num = int.random(1_000_000)
  let #(base_cid, base) = code(num)
  let #(other_cid, _other) = random_code()
  let p1 =
    ir.add(ir.release("foo", 1, base_cid), ir.integer(1))
    |> ir.map_annotation(fn(_) { [] })
  let p1_cid = cid_from_tree(p1)
  let p2 =
    ir.add(ir.release("foo", 1, other_cid), ir.integer(1))
    |> ir.map_annotation(fn(_) { [] })
  let p2_cid = cid_from_tree(p2)

  // base is already installed as a module so resolving the release will be able to complete
  let cache = cache.empty()
  let #(cache, _done) = cache.fetch_module_completed(cache, base_cid, Ok(base))
  let #(cache, _done) = cache.fetch_module_completed(cache, p1_cid, Ok(p1))
  let #(cache, _done) = cache.fetch_module_completed(cache, p2_cid, Ok(p2))

  let release = ir.Release("foo", 1, base_cid)
  let #(_cache, done) = cache.pulled(cache, 1, release)
  let done = dict.from_list(done)
  assert Ok(Ok(v.Integer(num + 1))) == dict.get(done, p1_cid)
  assert Ok(
      Error(
        break.UndefinedReference(ir.Pinned(ir.Release("foo", 1, other_cid))),
      ),
    )
    == dict.get(done, p2_cid)
}

pub fn resumption_to_bad_release_fails_test() {
  let num = int.random(1_000_000)
  let #(child_cid, child) = code(num)
  let #(other_cid, _other) = random_code()

  let parent =
    ir.add(ir.release("std", 1, child_cid), ir.release("std", 1, other_cid))
    |> ir.map_annotation(fn(_) { [] })
  let parent_cid = cid_from_tree(parent)

  let cache = cache.empty()

  let #(cache, done) =
    cache.fetch_module_completed(cache, parent_cid, Ok(parent))
  let assert Ok(cache.DependsOn(dep:, ..)) =
    dict.get(cache.fetching_modules, parent_cid)
  assert ir.Pinned(ir.Release("std", 1, child_cid)) == dep
  assert [] == done

  let assert #(cache, [effect]) = cache.flush(cache)
  assert cache.PullPackages(0) == effect
  let release = ir.Release("std", 1, child_cid)
  let #(cache, done) = cache.pulled(cache, 1, release)
  assert [] == done
  let #(cache, effects) = cache.flush(cache)
  assert [cache.FetchModule(child_cid)] == effects

  let #(cache, done) = cache.fetch_module_completed(cache, child_cid, Ok(child))
  let done = dict.from_list(done)
  assert Ok(Ok(v.Integer(num))) == dict.get(done, child_cid)
  let reason =
    break.UndefinedReference(ir.Pinned(ir.Release("std", 1, other_cid)))
  assert Ok(Error(reason)) == dict.get(done, parent_cid)

  assert dict.from_list([
      #(
        parent_cid,
        cache.Invalid(
          break.UndefinedReference(ir.Pinned(ir.Release("std", 1, other_cid))),
        ),
      ),
    ])
    == cache.fetching_modules
}

pub fn explicit_reference_lookup_test() {
  let #(first_cid, _) = code(1)
  let #(latest_cid, _) = code(2)
  let cache = cache.empty()

  assert cache.Available(first_cid)
    == cache.reference(cache, ir.Content(first_cid))
  assert cache.Unknown == cache.reference(cache, ir.Package("std"))
  assert cache.Unknown == cache.reference(cache, ir.Version("std", 1))
  assert cache.Unavailable(Nil) == cache.reference(cache, ir.Version("std", 0))
  assert cache.Unknown
    == cache.reference(cache, ir.Pinned(ir.Release("std", 1, first_cid)))
  assert cache.Unavailable(Nil)
    == cache.reference(cache, ir.Pinned(ir.Release("std", 0, first_cid)))
  assert cache.Unavailable(Nil)
    == cache.reference(cache, ir.Relative("./local.eyg"))

  let assert #(cache, []) =
    cache.pulled(cache, 2, ir.Release("std", 2, latest_cid))
  let assert #(cache, []) =
    cache.pulled(cache, 1, ir.Release("std", 1, first_cid))
  assert cache.Available(latest_cid)
    == cache.reference(cache, ir.Package("std"))
  assert cache.Available(first_cid)
    == cache.reference(cache, ir.Version("std", 1))
  assert cache.Available(first_cid)
    == cache.reference(cache, ir.Pinned(ir.Release("std", 1, first_cid)))
  assert cache.Unavailable(Nil)
    == cache.reference(cache, ir.Pinned(ir.Release("std", 1, latest_cid)))
}

pub fn package_and_version_references_resolve_test() {
  let #(first_cid, first) = code(10)
  let #(latest_cid, latest) = code(20)
  let cache = cache.empty()
  let #(cache, _) = cache.fetch_module_completed(cache, first_cid, Ok(first))
  let #(cache, _) = cache.fetch_module_completed(cache, latest_cid, Ok(latest))
  let #(cache, _) = cache.pulled(cache, 1, ir.Release("std", 1, first_cid))
  let #(cache, _) = cache.pulled(cache, 2, ir.Release("std", 2, latest_cid))
  let source =
    ir.add(ir.package("std"), ir.version("std", 1))
    |> ir.map_annotation(fn(_) { [] })
  let source_cid = cid_from_tree(source)

  let #(cache, done) =
    cache.fetch_module_completed(cache, source_cid, Ok(source))

  assert [#(source_cid, Ok(v.Integer(30)))] == done
  assert cache.Available(cache.Module(v.Integer(30), t.Integer))
    == cache.module(cache, source_cid)
}

pub fn missing_package_is_pulled_and_resolved_test() {
  let #(child_cid, child) = code(42)
  let source = ir.package("new") |> ir.map_annotation(fn(_) { [] })
  let source_cid = cid_from_tree(source)
  let #(cache, done) =
    cache.fetch_module_completed(cache.empty(), source_cid, Ok(source))
  assert [] == done
  let assert Ok(cache.DependsOn(ir.Package("new"), ..)) =
    dict.get(cache.fetching_modules, source_cid)
  let #(cache, effects) = cache.flush(cache)
  assert [cache.PullPackages(0)] == effects

  let #(cache, done) = cache.pulled(cache, 1, ir.Release("new", 1, child_cid))
  assert [] == done
  let #(cache, effects) = cache.flush(cache)
  assert [cache.FetchModule(child_cid)] == effects
  let #(cache, done) = cache.fetch_module_completed(cache, child_cid, Ok(child))
  assert [#(source_cid, Ok(v.Integer(42))), #(child_cid, Ok(v.Integer(42)))]
    == done
  assert dict.new() == cache.fetching_modules
}

pub fn relative_reference_is_rejected_without_effects_test() {
  let reference = ir.Relative("./local.eyg")
  let source = ir.relative("./local.eyg") |> ir.map_annotation(fn(_) { [] })
  let source_cid = cid_from_tree(source)
  let #(cache, done) =
    cache.fetch_module_completed(cache.empty(), source_cid, Ok(source))
  let reason = break.UndefinedReference(reference)

  assert [#(source_cid, Error(reason))] == done
  assert cache.Unavailable(reason) == cache.module(cache, source_cid)
  assert #(cache, []) == cache.flush(cache)
}

pub fn prepare_handles_every_reference_form_test() {
  let #(content_cid, _) = code(1)
  let #(pinned_cid, _) = code(2)
  let source =
    ir.list([
      ir.reference(content_cid),
      ir.package("latest"),
      ir.version("versioned", 1),
      ir.release("pinned", 1, pinned_cid),
      ir.relative("./local.eyg"),
    ])
  let #(cache, effects) = cache.prepare(cache.empty(), source) |> cache.flush

  assert 3 == list.length(effects)
  assert True == list.contains(effects, cache.FetchModule(content_cid))
  assert True == list.contains(effects, cache.FetchModule(pinned_cid))
  assert True == list.contains(effects, cache.PullPackages(0))
  assert cache.Pulling == cache.cursor_status
}

pub fn package_uses_latest_release_from_one_pull_test() {
  let #(first_cid, first) = code(1)
  let #(latest_cid, latest) = code(2)
  let cache = cache.empty()
  let #(cache, _) = cache.fetch_module_completed(cache, first_cid, Ok(first))
  let #(cache, _) = cache.fetch_module_completed(cache, latest_cid, Ok(latest))
  let source = ir.package("std") |> ir.map_annotation(fn(_) { [] })
  let source_cid = cid_from_tree(source)
  let #(cache, _) = cache.fetch_module_completed(cache, source_cid, Ok(source))
  let entries = [
    archived_release(1, ir.Release("std", 1, first_cid)),
    archived_release(2, ir.Release("std", 2, latest_cid)),
  ]

  let #(cache, done) = cache.pull_packages_completed(cache, Ok(entries))

  assert [#(source_cid, Ok(v.Integer(2)))] == done
  assert Ok(#(2, latest_cid)) == cache.package(cache, "std")
  assert cache.Pulled == cache.cursor_status
}

// test resumption with bad module value in part of an addition

fn archived_release(cursor, release) {
  let ir.Release(package:, version:, module:) = release
  let entry =
    substrate.Entry(
      sequence: version,
      previous: None,
      signatory: module,
      key: "test",
      content: publisher.Release(package:, version:, module:),
    )
  let assert Ok(payload) = publisher.to_bytes(entry) |> bit_array.to_string
  schema.package_entry(
    cursor:,
    cid: module,
    payload:,
    entity: module,
    sequence: version,
    previous: None,
    type_: "release",
  )
}

fn code(i) {
  let source =
    ir.integer(i)
    |> ir.map_annotation(fn(_) { [] })
  #(cid_from_tree(source), source)
}

fn random_code() {
  code(int.random(1_000_000))
}

pub fn cid_from_tree(source) {
  let cid.Sha256(bytes:, resume:) = cid.from_tree(source)
  resume(crypto.hash(crypto.Sha256, bytes))
}

/// A response is a completed pull whether or not it holds releases.
pub fn an_empty_successful_pull_is_complete_test() {
  let cache = cache.pull(cache.empty())
  let assert #(cache, [_effect]) = cache.flush(cache)

  let #(cache, done) = cache.pull_packages_completed(cache, Ok([]))
  assert [] == done
  assert cache.Pulled == cache.cursor_status

  // A later refresh can now queue another pull.
  let #(_cache, effects) = cache.pull(cache) |> cache.flush
  assert [cache.PullPackages(0)] == effects
}
