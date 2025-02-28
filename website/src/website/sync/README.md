# Package management (Sync)

Fetch and publish fragments and packages.

Is archive a better name, or dependency or package. sync message is a good name

# Fragment vs Package

A fragment is an EYG expression that is identified by it's hash.
A package consists of an ordered set of releases where each release points at a valid, pure fragment.

Pure means that the expression is side-effect free (it can contain functions with side effects), valid means that there are no type errors.

I want a term for valid fragments.
Calling invalid fragments blobs seems acceptable but I think for most people blob means binary.



## Cache
This is a local store for the package index and fragment store.

- Values in this cache never invalidate, so syncing is trivial.

The cache is modelled as a component with an `init` and `update` function.
It's up for the page to pass these in.
The cache may be used without making use of any of the view functions.

The cache also has synchronous API's. It could be modelled as an actor and communicate only my lustre messages.
However this would require each snippet to keep it's own cache of references that have been lookup up.
There is no point that when there is already a cache.

- The snippets can be considered message passing except a whole cache is cheaply transfered

### Index
The index contains all publish packages releases and all name registrations.

## Client is a browser client

It contains retry logic for the cache
This is the centerpoint for all coordination to pull down fragments.
Messages from users of the cache should be sent here.

As it coordinates with the outside world it should talk in terms of effects.
These can be midas effects, but we don't have a library for cid checking that works on midas.

## Remotes
Syncing is grouped by remote, this follows similar terminology as git.
Remotes are specific API's where references can be queries.

The runtime error remains a missin reference even if reference is known and release is still being looked up

# Notes

- Running code for the cache is pure so it doesn't need any understanding of an effectful runner.
- If evaluating the code results in a reference lookup, that has not yet been found it should be possible to resume.
  Views should query the cache store to show if reference is invalid or not found.
- There needs to be a record of cids that point to invalid content so that they don't keep getting reloaded

The supabase client defines a task that could be run in browser or server.


It is possible to load all fragments from checksums
