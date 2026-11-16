# Everything file system

## Wants

- A record of everything in my personal setup, i.e. transcripts, documents, invoices, tasks etc.
- Managed (type checked and authorized) changes over the code in an application.

Can code an data be unified, I want this because I want it to be easy for users to make changes, if they have permission, to the system.

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

### Downsides

The downside of the everything in one box file system is concurrency.
It's fair to call this a feature and a bug as simplifying the concurrency model to a single box was close to the early design goal.

The global name space for files does allow a simpler import pattern syntax. any definition of new events seems to require a full query language for imports or using EYG code and then an eval

Much higher concurrency is possible if we allow concurrent action.
This is the existing model when many shells are available on one machine.
The imports add extra guarantees on the shape of the files.

## Web interface

The website will be built using etui on howdy. As started on the howdy branch
It will have the same interface as sshing into the cloud service, although we aren't implementing that now.

The homepage is a neat full screen tui that allows you to setup a box.
In few operations a user should be able to set up a box and create rules for an agent in a slack channel that can only modify files in `/slack/channel/id` but it can read `app/skills` so that it can load app specific skills.

## Conclusion 

The first item to remove from the box concepts are events that have happened, i.e. not commands.
A web request is an event, even if it triggers a command.
Linux introduces sockets as a queing mechanism, this should not be necessary if logging is outside the core.
For example slack/discord events are logged outside the file system.
Form submissions are events logged outside, there can be a trigger on send, or a scheduled trigger can process with/without AI all the latest from the event stream.

Overlay trajectory traces are another external log source.
They can be read by shells/agents in the main file system, but they do not need to be imported using patterns

A Box is used as central configuration, this allows the simple pattern import solution to constrain configuration and accomodate upgrades in a type safe maner.
This configuration becomes Infrastructure as Code for larger systems, where the box configure queues and infra.
The initial file system can be a deploy script that sets up a server to listen to the box changes and implement them in the outside world.
There is a symetry between lots of messages out and the log (logs of messages in), for example if many emails need sending.
The read from the box builds a user query and template but post that as a single message to a configured external service that does the work.

The core file system changing under a long running process is also a feature.
It matches current OS/FS behaviour though it does result on hacks being worked out, like watchers
A shell/process will be able to a list of stale reads, files that have changed since they were last read.
This can be shown in a UI.

The core file system should be defined by `eyg_fs` whereas the cloud package includes services available as effects to shells/users.
such as publishing artifacts. The shells shouldn't publish an artifact instead the configuration as code set up in the box should specify what artifacts should be published

## Roadmap

1. 3 way merge on file changes, No merging of file changes and no move heuristics.
2. Type check a file system root, from fresh everytime no memoisation
3. Content Addressed store for both file systems and event attachements (such as large slack files)
4. Web frontend for shells in the cloud attached to a specific box.
5. View folders with correct index.html as artifacts. Linux uses file extension and mime type.

## Architecture

- packages/cloud.gleam starts processes for schedule, slack and discord. Secrets are loaded from environment and their is no account isolation
- `session.start` start a single process that manages all sessions. agent_session is a bad name as it holds the `overlay.Session` type which is better described as a configuration.

All of these component paths are under `src/cloud`

- app.gleam -> start supervision tree
- apex/router.gleam -> define http handlers, context type and middleware
- apex/public.gleam -> controller for routes that don't fit in a bounded context
- apex/public/terminal.gleam -> implementation of a terminal buffer so that etui can be used.
- apex/server.gleam -> start the webserver that
- box/configuration.gleam -> parsing/running eyg scripts for configuration
- box/controller.gleam -> define a box bounded context specific context type. This might split into an api.gleam and dashboard.gleam
- box/fs.gleam -> The implementation of type checking a file system, importing a pattern and a three way merge resolution. This will migrate to an eyg_fs or unifx package over time but for now is focused on just filling the box need
- box/cas.gleam -> definition of the types and messages for a content addressed store that works as a backend for mfs blocks
- box/cas_ets.gleam -> implementation of the (cas) backed by erlang term storage ETS, used for testing.
- schedule/controller.gleam -> schedules can be attached or not to a box.
- neon/api/client.gleam -> continuation based client
- neon/client.gleam -> Beam client passing in concrete fetch implementation
- neon/neon_cas.gleam -> neon implementation of CAS (This might move to data/blobs)
- artifacts/controller.gleam -> put new artifact based on car file or existing hash from mfs reference. Get artifact in embedded iframe so untrusted content works
- artifacts/driver.gleam -> API to use and snapshot an artifact.
- artifacts/preview.gleam -> show link previews
- sessions/api.gleam -> Create/execute/list existing sessions, sessions are shell or agent sessions. 
- data/events.gleam -> returns `pog.Query` types for all the relevant operations on the DB that use an event interface.
- data/boxes.gleam -> Boxes saved are events this module also includes queries into the views.
- data/session.gleam -> The state of a session such that it can be recovered. Sessions can also be forked.
  - Does fs reverting work in a session. if other things have happened around
  - storage should be based on an otel complient output
- otel/tracing.gleam -> implementation of tracing to build the session data

Migrations 

- priv/migrations/:migration -> managed by cigone