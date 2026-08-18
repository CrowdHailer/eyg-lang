All evaluation and type checking of code must be consistent across all the places it is used.
Implement the below tasks in order on the branch `depedency-resolution`
Everything should be tested before being implemented.
Use traversal functions in gleam_ir where sensible. Create new ones if necessary
For each task review what work can be extracted from pre-existing branches.

## Tasks

- [ ] implement a new package called gar that allows working with CAR files in Gleam.
  - [ ] rework the solution, bug fixes and tests found on branch `bot/resolution`
  - [ ] Do not try an publish to hex depend on as a path dependency
- [ ] create a function `tree.pin(node:, resolve_relative: fn(String) -> K(t, Cid), resolve_unpinned: fn(String, Option(Int)) -> K(t, #(String, Int, Cid)))` that builds on the rewrite tree traversal to build a pinned tree.
- [ ] Use tree.pin in the cli share command. It should resolve relative references from the file system and unpinned releases from the current cache
  - [ ] The implementation of the computation around tree.pin should build up a state of all relative references loaded from the file system and their hash, this is then serialized as car file.
- [ ] Implement on a single commit any bug fixes from the branch `bot/resolution` that can be extracted WITHOUT changing anything else, i.e. do not refactor releases or errors.
- [ ] Measure how deep inference can go before stack runs out. Take work from `bot/resolution` but build on the current inference implementation
- [ ] let inference ask for the references it needs take work from `bot/resolution`
  - [ ] Show there is no regression on how deep the stack can go
  - [ ] Write general notes about using traverse functions in inference and how it effects performance
- [ ] Update the hub backend so the share endpoint accepts a car file.
  - [ ] switch between car file and single module on content-type
  - [ ] use a single inference pass to check upload is valid, review branch `bot/hub-checks-modules`
- [ ] review branch `bot/cache-resolves-packages` if any work remains from that rework it onto this branch.