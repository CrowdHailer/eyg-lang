# Everything file system

## Immutability has no existance

EYG is a functional immutable language.
This means that there is no concept of self an EYG can process data but not modify itself.

One solution is to identify a computer as the concept of self.
Essentially I equate existance to a timeline of mutable state.
The computer consists as a set of processes and kernel state living on a file system. Is there anything missing that should be considered a core part of an operating system that is relevant for this discussion.

This is not the only solution for the concept of identity.
A spread sheet is another layout of mutable items that can evolve over time.
Mutable variables in a program are close, they also require eval to load in new code

An entity that exists (has a mutable timeline regardless of implementation) has additional properties
- Snapshot the entity at a given point in time
- Clone, evolve more than one instance forward from a snapshot.

The fact that a system has these properties does not imply that the implementation of these properties is efficient.

The file system is a long established solution to a computable system having an existence.

However the file system abstraction has downsides (we'll consider which of these are important or workable later).
- There is no standard reconsiliation approach for concurrent access.
- Unix has a built in concept of users and groups, that is not fine grained enough for all usecases.
- With everything in a file system several work arounds come into existance. One is watching for changes.

For now my goal is to create an incredibly intuitive set of primitives for build a cloud native system with an evolvable existance.
It doesn't need to handle scaling i.e. lots of concurrent actors.

Example use of the file system.

Once setup systemd is the single process that is booted as part of turning on a computer.
Configuration of what is running is set up in systemd config files. Where do these live what is the format?

Installing php (is it php or apache) is pointed at applications with a config file on the file system. What are the details here?

More recently vercel/nexjs use layout of a project on the file system to specify how an application works.

A global mutable file system is not something that is type checked programs that load data/config have to have runtime errors for any dependencies on the file system.

## EYG FS

Everything in an EYG box builds on the EYG file system

This builds upon Mutable File System (MFS) a box (is this a good name).

> The external API cannot be based on hashes if a reader is limited in it's ability to read directories
> To create a new hash tree the client must be able to reproduce all parent directories.
> This access to directories does not require any access to file content.
>
> A future API could check that directory read access is always allowed.
> A good API would be post to a name a CAR file with new root CID, all new blocks are expected.
> 
> For now an external API to modifying files is exposed only to the sudo role with ability to post a new file root.
> The other option for a client is to run a script and the runtime will manage all new hash values. Only one script runs at a time.

### A box

A box is the changable container for one chain of MFS roots.
Cloning a box creates a new box with a new name and the same file system root.

### import checking

Any change to an EYG FS also validates any imports.
Imports are resolved against the file system.

#### Simple imports

```eyg
// /entry.eyg
!int_add(import "./foo.eyg", import "./bar.eyg")
```

When this file is included in an filesystem the whole system is checked and both `foo.eyg` and `bar.eyg` must exist and contain modules that return an `Integer`.

#### Pattern imports

Pattern imports are for loading a set of modules.
The return of the 

```eyg
let blogs = import "./blog/[slug].eyg"
let routes = import "./routes/[..slug].eyg"
let blogs = import "./site/[latitude]/[longitude].eyg"
```

The type of blogs is `List({slug: String, value: t})`
The type of routes is `List({slug: List(String), value: t})`
The type of routes is `List({latitude: String, longitude: String, value: t})`

#### Blob imports

Importing a single file that does not end in a `.eyg` or `.eyg.json` returns the files binary content.
Pattern imports also work

```eyg
let logo = import "/images/logo.jpg"
let pngs = import "/images/[image].png"
```

#### Hub imports

All EYG scripts can rely on published packages e.g. `@standard`.
Caching is done on the level of the whole cloud so in most cases this is a cheap dependency and saves space in the box.

#### Implementation

Type checking the whole file system is applied to an MFS root.
The checking algorithm traverses all files.
Checking follows imports but tracks:
- the files already checked so each is checked only once
- the current import sequence to avoid import loops.

The type checking algorithm also accepts a previous run state so only the changed files are checked.

## EYG computer

### Configuration

There is one special file in the EYG computer `_box/config.eyg`.
Access to the `_box` dir has an additional check external to the box configuration that ensures that only the admin user can read and modify it.

### Secrets

Secrets are set as env variables per box.
They can be used in `_box/config.eyg` via the `Env` effect.
It is good practise for all users to have calls to perform the `Env` effect denied.
Instead for fetch requests a derived identifier is passed and the policy for fetch replaces that identifier with the actual token in headers.

### Services

The configuration file is an EYG module that returns an object with a field for each service the box supports, for example HTTP, ssh or provider specific such as Slack

Each box gets it's own subdomain on cloud.eyg.run, this is the domain for http and ssh (but not web as that log in is from the main cloud page.)

Note in all cases policies for `ReadFile` also apply to imports.

#### ssh

```eyg
// /_box/config.eyg
{
  ssh: {
    port: 22,
    bind: (attemted_user, key) -> {
      let users = import "/home/[user].eyg"
      // find user and check key, there is a field `ssh.authorized_keys in the user.eyg file
      {policy: policy, process: Shell({}) | Overlay({prompt: "read skills from \"/shared/skills/skill.md\"", llm:})}
    }
  }
}
```


This pattern allows a user to change their own keys but without read/write access to `config.eyg` or other user directories that's all they can change.

Note the overlay agent is an option to start instead of a shell.
This should be deprecated once an Agent can be built purely in EYG.

#### The web

```eyg
// /_box/config.eyg
{
  http: {
    ip: 0.0.0.0, // accept all domains.
    port: 80,
    on_request: (request) -> {
      let users = import "/shared/routes/[route].eyg"
    }
  }
  web: {
    bind: (user) -> {
      {policy: policy, process: Shell({}) | Overlay({..})}
    }
  }
}
```

The `http` field binds for webhooks.
The `web` field is for anyone who is logged into `cloud.eyg.run` who connects to a box.
They will get a shell or a agent session with the same configuration as overlay policy already implemented in gleam_cli

The web view also gets a file browser where each dir with an `index.html` is viewable as an artifact.

#### Channels

Channels are described in `packages/cloud/README.md`

```
// /_box/config.eyg
{
  slack: {
    connection: { bot_token: perform Env("MY_COMPANY_SLACK_BOT_TOKEN") }
    entry: (channel) -> {
      {policy: policy, process: Overlay({})}
    }
  }
}
```

Note there is also a both process option for shell execution when it's valid EYG.

#### Service Notes

Service logs live outside the file system.

All invocations and tracing information is saved in an OTEL format outside the box.

A service invocation finished before another executes.
The only exception is Overlay where each turn completes before the next execution.

## Web interface

The website will be built using etui on howdy. As started on the howdy branch
It will have the same interface as sshing into the cloud service, although we aren't implementing that now.

The homepage is a neat full screen tui that allows you to setup a box.
In few operations a user should be able to set up a box and create rules for an agent in a slack channel that can only modify files in `/slack/channel/id` but it can read `app/skills` so that it can load app specific skills.

