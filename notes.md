---
name: Bundle branch review
description: Correctness errors found while reviewing CAR upload and sharing modules by hash.
date: 2026-09-05
---

# Bundle branch review

## Confirmed errors

- Fixed: Transitive relative-import cycles were not tracked while building a share bundle, so a graph such as `root -> A -> B -> A` recursed indefinitely.
- Fixed: Shared relative imports were reread, reparsed, and rehashed once per path through a diamond dependency graph.
- Fixed: Modules fetched by content identifier were accepted by reusable clients without checking that the returned module had the requested hash.
- Fixed: The first reusable CID verifier depended on Node crypto and broke production browser bundles.
- Fixed: Its handwritten browser SHA-256 replacement mishandled Gleam JavaScript bit arrays; hashing now uses the existing platform hash effect and Web Crypto.
- Fixed: Reusable share clients accepted a response CID that differed from the locally calculated root.
- Fixed: The publish path accepted a response CID that differed from the module it was about to sign.
- Fixed: The share client reduced useful HTTP failures to `bad module lookup`.
- Fixed: The bundle share client discarded actionable rejection reasons returned by the Hub.
- Fixed: Hub module lookup validated a parsed CID but queried with the original, potentially noncanonical URL text.
- Fixed: The CAR endpoint rejected valid archives whose root was not the first block or which contained unreachable blocks instead of shaking them to the graph reachable from the declared root.
- Fixed: CAR shaking decoded every supplied block before reachability and used quadratic list lookups, so an invalid unreachable block rejected the upload and wide archives consumed excessive CPU.
- Fixed: Upload size limits were checked only after Wisp had buffered the complete request body.
- Fixed: Pinned references were accepted by module CID without validating their package and version against the release ledger.
- Fixed: Stored dependency source was trusted without checking that its canonical module matched the database CID.
- Fixed: Re-uploading a valid module reported success while leaving conflicting corrupt stored source unchanged.
- Fixed: Recursive stored dependency validation had no cycle guard.
- Fixed: Bundle uploads amplified retries into per-block audit rows and attributed every upload to a fabricated IP address.

## Verification errors

- Resolved locally: Compose-created `dist` and `node_modules` directories were owned by root, preventing host production builds. Ownership was repaired through the running containers.
- Corrected command: The website has no npm `build` script; its production build is `gleam dev build`.
- Resolved locally: The website's host `node_modules` was incomplete; `npm install` restored the declared dependencies before the successful build.
- Resolved locally: The installed `eyg` executable cannot handle the checkout's `StandardOut` effect; repository EYG tests must run through the checkout's CLI.
