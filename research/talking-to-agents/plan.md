# Organisation

An organisation (workspace) is a consistency boundary. https://dcb.events/#dcb-approach
Roles/teams/permissions/listeners all live in one consistency boundary.

File systems are per process, artifacts are per organisation

A conversation is an abstraction over the shape of communication.

In Slack the [conversation API](https://docs.slack.dev/apis/web-api/using-the-conversations-api) covers public channels, private channels, direct messages, group direct messages, shared channels.

OpenClaw names them direct, group, named

Complexity arises from editing messages, replies, threads.

Replies can be represented inline

Each Adapter can integrate to more than one instance
is a Forum a good name, or surface. or medium or community or entry


There are integrations that provide secrets, and integrations that provide a new surface

Events

```
ConnectedSlack(bot_token: String) -> This creates an identifier so triggers
SetSlackBinding(fn(channel) -> session name)
UpdatedTrigger(name: String, revision: Int, connection: Slack(id: , code: #ref)) -> revision 0 creates a new trigger
DeletedTrigger(name: revision:) -> revision is used as a concurrency lock

SlackEvent
DiscordEvent
RssEvent
UpdatedCron

```




```eyg
// slack is a connection and entry to the sytem
let slack = {
  // The connection defines a slack workspace and therefor a name
  connection: {bot_token: "reference to secret"}
  // independent sessions creates a function from structured slack channel information to a session_id
  entry: independent_sessions,
  trigger: [
    {name, function, policy}
  ]
}



// multiple conversations need to be able to get to the same process
// It'd be helpful to define 


let slack_connection = ({workspace, event}) -> {

}
// connection deny all but connect
let shells = [
  {name: "peter", policy: allow all}
]
policies = (name) -> {
  policy
}
process = (source) -> {
  Agent | Shell
}

connect is an effect that's allowed
let processes = [
  {name: ""}
]
let ssh = {
  port: 22
  bindings: {
    [{
      user: "peter", keys: []
    }]
  }
}
```

Tmux defines session as a named thing to reconnect to. so a new ssh session on a machine is ephemeral
but you connect to a server to find the existing one. 


A workspace (maybe I need a new name) doesn't necessarily need email login, we have ssh etc

- Connections, Channel connections
- Triggers
- Shells/sessions

## Transparent blob/event store

Events can reference large blobs

There should be search/vector APIs over this

- Bring your own storage to [turbopuffer](https://turbopuffer.com/)
  - https://zilliz.com opensource alternative
- [XTDB](https://xtdb.com/) and [terminus](https://terminusdb.com) give point in time querying of DB's.
  Bring your own schema and s3 storage
- perkeep interesting consumer focused thing

## Agents you directly add to slack etc

- [Lindy](https://www.lindy.ai/) Good plug and play option
- https://viktor.com/blog/best-ai-agents-for-slack several options
- https://dust.tt/home/product dust


## Task based things
- https://deft.co/#manifesto#about Good website
- [ABRA: Agent-Bound UI for Human–Agent Communication beyond Chat with Reusable Views](https://arxiv.org/html/2610.30780)


Everything as a dag, write derived from functions
