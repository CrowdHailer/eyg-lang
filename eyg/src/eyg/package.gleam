// import eyg/analysis/type_/binding/error
// import eyg/document/section
// import eyg/interpreter/value as v
// import eyg/ir/tree as ir
// import eyg/parse
// import gleam/io
// import gleam/list
// import gleam/listx
// import gleam/result
// import morph/editable
// import website/sync/sync

// pub type Scope =
//   List(#(String, String))

// pub type Section {
//   Section(content: section.Section, computed: Computed)
// }

// type Path =
//   List(Int)

// // A package is a list of sections where each section consits of a list of comments and an snippet
// // a snippet is a list of assignments there are no unassigned values

// // errors range over the whole snippet
// // refs
// // So the errord values cant make it into the reference cache because metadata is not part of the exp
// pub type Computed {
//   Computed(
//     // references is all the assignments
//     references: List(String),
//     errors: List(#(Path, error.Reason)),
//     final: Scope,
//   )
// }

// // assignments are a list of editable assignments in this guide
// // types are the top level type of each assignment, and should be zipped with assignments
// // types order is reversed to match with the assignments that are top to bottom
// // errors don't have an order and so are not reversed
// fn do_load_snippet(
//   assignments,
//   index,
//   refs,
//   errors,
//   scope: Scope,
//   cache: sync.Sync,
// ) {
//   case assignments {
//     [] -> #(cache, Computed(list.reverse(refs), errors, scope))
//     [assignment, ..assignments] -> {
//       let #(pattern, source) = assignment

//       // self contained = no free variables
//       // editable.to_annotated has the path information as the metadata
//       let contained: ir.Node(_) =
//         source
//         |> editable.to_annotated([1, index])
//         // |> ir.substitute_for_references(scope)
//         |> todo

//       let ref = todo
//       let refs = [ref, ..refs]

//       let cache = sync.install(cache, ref, contained)
//       let executed = case sync.value(cache, ref) {
//         Ok(sync.Computed(value: executed, ..)) -> executed
//         Error(Nil) -> Error("Something bad happend executing value")
//       }

//       // let errors = list.append(new_errors, errors)

//       let #(cache, scope) = case pattern, executed {
//         editable.Bind(label), _ -> #(cache, [#(label, ref), ..scope])
//         editable.Destructure(pair), Ok(v.Record(fields)) ->
//           list.fold(pair, #(cache, scope), fn(acc, pair) {
//             let #(cache, scope) = acc
//             let #(field, bind) = pair
//             let contained = #(
//               ir.Apply(#(ir.Select(field), []), #(ir.Reference(ref), [])),
//               [],
//             )

//             let ref = todo
//             io.debug(#(field, ref))
//             let cache = sync.install(cache, ref, contained)

//             let scope = [#(bind, ref), ..scope]
//             #(cache, scope)
//           })
//         editable.Destructure(pair), x -> {
//           io.debug(pair)
//           io.debug(x)
//           io.debug("need to add something for refs in destructure case")

//           #(cache, scope)
//         }
//       }

//       do_load_snippet(assignments, index + 1, refs, errors, scope, cache)
//     }
//   }
// }

// pub fn load_snippet(snippet, scope, cache) {
//   do_load_snippet(snippet, 0, [], [], scope, cache)
// }

// pub fn load_guide_from_bytes(bytes, cache) {
//   use source <- result.try(sync.decode_bytes(bytes))
//   Ok(load_guide_from_expression(source, cache))
// }

// pub fn load_guide_from_expression(source, cache) {
//   let #(sections, _) = section.from_expression(source)
//   load_guide(sections, cache)
// }

// pub fn load_guide(sections, cache) {
//   let #(cache, before) = do_eval_sections(sections, [], [], cache)
//   build_guide(cache, before)
// }

// pub fn sections_from_content(content) {
//   list.map(content, fn(c) {
//     let #(comments, code) = c
//     let assert Ok(#(#(source, _then), _)) = parse.block_from_string(code)
//     let source =
//       list.fold(source, #(ir.Vacant, #(0, 0)), fn(acc, assign) {
//         let #(label, value, meta) = assign
//         #(ir.Let(label, value, acc), meta)
//       })
//     let assert editable.Block(assigns, _, _) = editable.from_annotated(source)

//     section.Section(comments, assigns)
//   })
// }

// pub fn load_guide_from_content(content, cache) {
//   let sections = sections_from_content(content)
//   load_guide(sections, cache)
// }

// pub fn build_guide(cache: sync.Sync, before) {
//   let public = public_fields(before)
//   let exports = exports(public, [])
//   let public = listx.keys(public)

//   let ref = todo
//   let cache = sync.install(cache, ref, exports)
//   #(cache, before, public, ref)
// }

// // content is a list of sections, before is the reversed list of section + cached calculation
// // guide has sections reversed in before position so we don't reverse here
// // TODO references need to update
// pub fn do_eval_sections(content, before, scope: Scope, cache) {
//   case content {
//     [] -> #(cache, before)
//     [section, ..content] -> {
//       let section.Section(_comments, snippet) = section
//       let #(cache, computed) = load_snippet(snippet, scope, cache)
//       let before = [Section(section, computed), ..before]
//       do_eval_sections(content, before, computed.final, cache)
//     }
//   }
// }

// // expects reversed
// fn exports(public, meta) {
//   list.fold(public, #(ir.Empty, meta), fn(rest, field) {
//     let #(label, ref) = field
//     #(
//       ir.Apply(
//         #(ir.Apply(#(ir.Extend(label), meta), #(ir.Reference(ref), meta)), meta),
//         rest,
//       ),
//       meta,
//     )
//   })
// }

// fn public_fields(before) {
//   case before {
//     [Section(computed: computed, ..), ..] -> {
//       do_gather_public(computed.final, [])
//     }
//     _ -> []
//   }
// }

// // this doesn't reverse the accumulator
// fn do_gather_public(scope, acc) {
//   case scope {
//     [] -> acc
//     [#(label, ref), ..rest] ->
//       case list.key_find(acc, label) {
//         Ok(_) -> do_gather_public(rest, acc)
//         Error(Nil) -> do_gather_public(rest, [#(label, ref), ..acc])
//       }
//   }
// }

// pub fn scope_at(before) {
//   case before {
//     [Section(computed: computed, ..), ..] -> computed.final
//     [] -> []
//   }
// }
