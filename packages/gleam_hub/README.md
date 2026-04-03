# Gleam hub

Schemas, encoders and decoders for the EYG Hub API.
Implement the "sans io" pattern; types and functions can be used on both erlang and JavaScript runtimes.

## The EYG Hub

Save and share EYG code.
Unstructured sharing of modules is possible, they are identified by their content identifier (CID).

Modules can also be published as package releases.
Each release is signed to create a trust chain for accepting new releases.

Signatories are mutable collections of keypairs that may sign releases, all updates to a signatory are also signed.

### Modules vs expressions

Any EYG expression can be identified by its Content Identifier (CID).
When an expression has no type errors it is sound.
When an expression has no side effects it is pure.
A module is a sound and pure expression.

**Only modules can be shared on the EYG Hub.**

### Packages and Releases

A package consists of an ordered set of releases.
Releases have a version number which is monotonically increasing value and a timestamp recording when they were published.
Each release references a module, entrypoint of the package.
A package is identified by its ID and version.
Releases are immutable and can only be revoked, not modified, after publishing.

**Package names can be assigned new signatories.** New signatories will be unable to modify previous release and have to continue the release sequence.
Any reassignment is visible in the signatory trust chain.

## Endpoints

### Share module
`/modules/share`

Share a module on the hub and receive it's CID.

### Get module
`modules/:cid`

Get a module by its CID.

### Submit signatory entry
`signatories/submit`

### Pull signatory entries
`signatories/pull`

### Submit package release
`packages/submit`

Publish a new release for a package.
Note the module id but be of a previously shared module.

### Pull packages releases
`packages/pull`

## Notes

### Old names

#### The registry and archive
Previously used as domain terms for managing packages and modules.
The term "hub" has been used for the whole service and also includes managing signatories