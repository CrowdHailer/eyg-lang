The source for all supported EYG packages are is in `eyg_packages`.
The supported packages have an `index.eyg` `test.eyg` and `entry.eyg`.
Reference the `http` and `aok` packages and follow there structure.

Modules can be shared, or published.
When shared the module is available by it's hash.
A published release consists of a package name version number and module hash.

We need to add checks that ensure everytime eyg_package code is pushed to main that it matches the latest published release.

## Checks

The check is
- pull all packages from the hub and find the latest release and it's hash.
- For each package in eyg_packages:
  - check if a published package has the same name as the eyg_package `eyg_packages/<package_name>/index.eyg`
  - If there is no published package then all is ok.
  - If there is a published package check that the hash of the `index.eyg` or `index.eyg.json` file is the same as the published module. refer to hashing guidelines below.
  - If the hashes do not match then print the error and track that the script should return a non zero exit code.

## hashing
EYG modules are hashed by their canonicalized DAG JSON representation.
To calculate the hash parse the file to it's AST serialize with dag json and compute the cid.

## Technical setup

- This check should be implemented entirely in EYG. it should be part of the script that is run by running `eyg entry.eyg` at the repo top level.
- Minimal code should be added to the top level `entry.eyg` file.
- All added code should be broken into useful modules, and completly tested.
- Update packages such as @eyg with a hub module as an API client.
- An API client should separate builting operations from dispatching them to an origin. See the http packe for details.

## Important

- record all technical difficulties encountered while working.
- track any future work
- commit regularly and push.