---
name: Event catalogue
description: Every domain event agreed in the event storming session, with its command, actor, aggregate and the policies it triggers.
---

# Event catalogue

Generated from [the final board](./boards/final_board.json). Events are in time order within each bounded context.
Policies are the reactions an event triggers, often in another context.

## Identity

Who people and API clients are and how they prove it. Authentication only, grants live in access.

| Event | Command | Actor | Aggregate | Policies |
| --- | --- | --- | --- | --- |
| `CloudBootstrapped` | BootstrapCloud (one-time code printed by the server) | Operator at the server console | CloudInstallation | Whenever CloudBootstrapped, GrantAdmin to the bootstrapping person (the only grant that needs no approval) |
| `PersonInvited` | InvitePerson (with proposed shell) | Admin (person) | Person |  |
| `PersonSignedUp` | AcceptInvitation | Invited person | Person | Whenever PersonSignedUp, AssignPersonShell to the invitation's shell (through a PrivilegeChange if it is wider than the default shell) |
| `PersonSignedIn` | SignIn | Person | Person |  |
| `SignInRejected` | SignIn (rejected: unknown subject, deactivated, bad assertion, throttled) | Unknown visitor | Person | Whenever SignInRejected passes a threshold for a subject or source, throttle SignIn for it and alert admins |
| `ApiCredentialIssued` | IssueApiCredential (scoped to a shell no wider than the issuer's) | Admin or person issuing a credential for themself | Credential |  |
| `CredentialRevoked` | RevokeCredential | Admin, the credential's owner, or a revocation policy | Credential | Whenever CredentialRevoked for a web shell session, UnbindFromChannel and close the live view |
| `PersonDeactivated` | DeactivatePerson | Admin (person) | Person | Whenever PersonDeactivated, keep all attribution: deactivation never triggers erasure by itself<br>Whenever identity.PersonDeactivated, CancelRun for every live or suspended run whose on_behalf_of chain ends in that person<br>Whenever PersonDeactivated, RevokeCredential for all their credentials, UnbindFromChannel everywhere, and RevokeAdmin<br>Whenever PersonDeactivated, list every secret they set or rotated as 'known by a departed person' and propose RotateSecret |

Read models:

- People: provider and subject, status, shell, admin flag, active credentials with issue, expiry and last use
- Sign-in failures by subject and source (operator security view)
- Dormant and long-lived credentials (unused for 30 days, no expiry)

## Access

Who may do what: shell definitions, channel shells, person shells, admin, bindings, and proposals that widen privilege.

| Event | Command | Actor | Aggregate | Policies |
| --- | --- | --- | --- | --- |
| `ShellDefinitionPublished` | PublishShellDefinitions (from a cloud.eyg version) | Admin editing cloud.eyg, applied after approval when any shell widens | ShellCatalog | Whenever ShellDefinitionPublished removes a shell name, AssignPersonShell to the default (least) shell for everyone who held it |
| `ChannelShellChanged` | RecordChannelShells (diff of channel shell CIDs) |  | ChannelAccess | Whenever access.ChannelShellChanged or access.PersonShellAssigned, live runs pick up the new shell at their next effect decision, recorded as RunResumedUnderNewShell |
| `PrivilegeChangeProposed` | ProposePrivilegeChange (carries the exact command to apply and the expected version of its target) | Admin, person, or agent acting for a person | PrivilegeChange |  |
| `PrivilegeChangeApproved` | ApprovePrivilegeChange | Second admin (a person signed in within 15 minutes, never an agent, trigger, schedule or API credential) | PrivilegeChange | Whenever PrivilegeChangeApproved for a configuration version, ApplyWorkspaceConfiguration for that version if it is still the latest source; whenever PrivilegeChangeDeclined, RejectWorkspaceConfiguration<br>Whenever PrivilegeChangeApproved, issue the proposed command (GrantAdmin, AssignPersonShell, ApplyWorkspaceConfiguration, PublishShellDefinitions, TrustSignatory, CreateUnauthenticatedConnection) with the approval as causation<br>Whenever access.PrivilegeChangeApproved for an artifact's visibility, SetArtifactVisibility |
| `PrivilegeChangeDeclined` | DeclinePrivilegeChange | Admin (person) or the proposer withdrawing | PrivilegeChange | Whenever PrivilegeChangeDeclined for a held configuration, notify the proposer's channel and leave the previous configuration in force |
| `PrivilegeChangeExpired` |  |  | PrivilegeChange |  |
| `AdminGranted` | GrantAdmin | Approval policy (after PrivilegeChangeApproved) or bootstrap policy | PersonGrants |  |
| `AdminRevoked` | RevokeAdmin (no approval needed, refused if it would leave no admin) | Admin (person) or deactivation policy | PersonGrants |  |
| `PersonShellAssigned` | AssignPersonShell (the SetUserShell operation) | Admin (directly when narrowing, through the approval policy when widening) | PersonGrants | Whenever PersonShellAssigned or AdminRevoked, re-prepare the person's live web shells and RevokeCredential for API credentials scoped wider than the new shell |
| `PersonBoundToChannel` | BindToChannel (Bind effect from the web shell) | Person in the web shell | PersonGrants |  |
| `PersonUnboundFromChannel` | UnbindFromChannel | Person, or the revocation and deactivation policies | PersonGrants |  |

Read models:

- Access matrix as of time T: for each person, credential, channel and agent, which effects it may perform, which shell CID grants them, and which configuration and approval produced it
- Pending privilege proposals: diff, proposer and on-behalf-of chain, expiry (the admin queue)
- Privilege change history with proposer, approver and causation (the auditor's view)
- Admins and break-glass status (sole admin, self-approvals used)
- Exposure: unauthenticated connections, shared artifacts, channels whose shell holds fetch plus a secret

## Workspace configuration

Versions of workspace.eyg by source CID and the moment a version takes effect.

| Event | Command | Actor | Aggregate | Policies |
| --- | --- | --- | --- | --- |
| `CloudSourceChanged` | SetCloudSource {source_cid, expected_previous_cid, reason, restores?} | Admin (person) | CloudConfiguration |  |
| `WorkspaceCreated` | CreateWorkspace | Admin (person), via cloud.eyg or the admin page | WorkspaceConfiguration | Whenever configuration.WorkspaceCreated with a seed directory, WriteFile/MakeDirectory for each seed entry (actor = configuration version) |
| `WorkspaceSourceChanged` | SetWorkspaceSource {workspace, source_cid, expected_previous_cid, reason, restores?} | Workspace maintainer (person) in the web shell or POST /api/SetWorkspaceSource<br>Agent with a set_workspace_source gate, on behalf of the person at the root of its chain | WorkspaceConfiguration | Whenever WorkspaceSourceChanged, evaluate the new source purely: if it fails, RejectWorkspaceConfiguration; if it changes any channel shell, person shell or admin, ProposePrivilegeChange (access) and wait; otherwise ApplyWorkspaceConfiguration<br>Whenever WorkspaceSourceChanged, PinContentRoot for the source CID so every configuration version stays readable for its retention period (content)<br>Whenever WorkspaceSourceChanged and the new source adds an effect field to a channel shell, changes a configuration-API, secret or admin gate, or changes a secret's allowed hosts, ProposePrivilegeChange and hold ApplyWorkspaceConfiguration until it is approved<br>Whenever configuration.WorkspaceSourceChanged, TagFileSystemSnapshot('before config <source CID>') so a configuration revert can come with a file restore |
| `WorkspaceConfigurationApplied` | ApplyWorkspaceConfiguration {source_cid, evaluated_config_cid, secret_names_read, basis} | Configuration evaluator (system process, pure evaluation of workspace.eyg) | WorkspaceConfiguration | Whenever WorkspaceConfigurationApplied, reconcile what it declares: SaveTriggerToWorkspace / ShadowTrigger (triggers), SetRecurringSchedule (schedules), ConnectService (connections), ChangeChannelShell (access). Each resulting event cites the applied version as its cause<br>Whenever configuration.WorkspaceConfigurationApplied, reconcile configured crons: SetRecurringSchedule for new or changed, CancelSchedule for removed<br>Whenever configuration.WorkspaceConfigurationApplied defines a trigger whose name a runtime trigger uses, ShadowTrigger<br>Whenever WorkspaceConfigurationApplied, RecordChannelShells for every channel whose shell CID changed<br>Whenever configuration.WorkspaceConfigurationApplied, reconcile connections: ConnectConnection for each new or changed one, DisconnectConnection for each removed one |
| `WorkspaceConfigurationRejected` | RejectWorkspaceConfiguration {source_cid, reason} | Configuration evaluator (system process) | WorkspaceConfiguration | Whenever WorkspaceConfigurationRejected, post the evaluation error to the author and keep the previous version in force |

Read models:

- Configuration history per workspace: version, source CID, author and on_behalf_of chain, reason, restores, applied or rejected, approval reference, diff against the previous version
- Policy in force at time T: for any global position, which configuration version, channel shells, person shells and admins applied, by CID. Answers 'what was this agent allowed to do last March'
- Revert impact: for a restored version, the effects performed under the versions in between that a revert does not undo

## Secrets

Secret values live in a vault, events record names, versions and keyed fingerprints only.

| Event | Command | Actor | Aggregate | Policies |
| --- | --- | --- | --- | --- |
| `SecretSet` | SetSecret: the event gets name, version and keyed fingerprint, the vault issues the opaque handle | Admin (person at the root of the actor chain; an agent can only propose) | SecretVault |  |
| `SecretRotated` | RotateSecret | Admin, or a person answering a rotation alert | SecretVault | Whenever SecretRotated for a name listed in the applied configuration's secret_names_read, ApplyWorkspaceConfiguration again with the same source CID<br>Whenever SecretRotated or SecretDeleted, ApplyWorkspaceConfiguration again for every workspace whose last WorkspaceConfigurationApplied read that secret |
| `SecretInjectedIntoRequest` | InjectSecret (egress replaces the opaque handle for an allowed host) | Egress gateway (system) | SecretEgress |  |
| `SecretInjectionRefused` | InjectSecret (refused: host not allowed, secret deleted, handle from a retired version) |  | SecretEgress | Whenever SecretInjectionRefused, fail the Fetch step (EffectFailed) and alert workspace admins with the actor chain: a placeholder sent to the wrong host is a likely exfiltration attempt |
| `SecretLeakRedacted` | RedactPayload (scan for known values and handles before EffectResultRecorded, MessagePosted, MessageReceived, FileWritten) | Redactor (system) | LeakRegister | Whenever SecretLeakRedacted, alert admins and ProposeRotation of that secret (a value seen in a payload is treated as exposed) |
| `SecretDeleted` | DeleteSecret (crypto-erases the value in the vault) | Admin, or the disconnect policy | SecretVault | Whenever secrets.SecretDeleted or secrets.SecretRotated for a secret a connection read, re-apply the workspace configuration, which connects, reconnects or disconnects it |

Read models:

- Secret inventory: name, current version, fingerprint, set and rotated by, age, allowed hosts, configurations reading it, last used
- Secret usage: per secret version, hosts, runs and actor chains that used it (the auditor's 'who used the Stripe key')
- Security alerts: refused injections and redactions by run, channel and actor
- Rotation due: secrets older than policy, known by departed people, or seen in a payload

## Code by hash

Signatories, signed releases, verification, and workspaces pinning releases by hash.

| Event | Command | Actor | Aggregate | Policies |
| --- | --- | --- | --- | --- |
| `SignatoryTrusted` | TrustSignatory (key fingerprint and name scope, e.g. @acme/*) | Admin, applied after PrivilegeChangeApproved | TrustStore |  |
| `ModulePublished` | PublishModule | Publisher (person, or agent with a hub publishing shell) | PackageRelease |  |
| `ReleaseSigned` | SignRelease | Publisher holding a signatory key | PackageRelease |  |
| `PackageSignatureVerified` | VerifyRelease (hash of fetched bytes equals CID, signature by a trusted key in scope, release not retracted) | Run loader (system) | ReleaseVerification |  |
| `PackageVerificationFailed` | VerifyRelease (failed: hash mismatch, unknown or revoked signer, out of scope) |  | ReleaseVerification | Whenever PackageVerificationFailed, FailRun for the run that needed it (no step evaluated) and alert the channel and admins |
| `PackagePinned` | PinPackage (only a verified release) | Person, or agent for a person (code runs inside the channel shell, so this is not a privilege change) | WorkspacePins |  |
| `ReleaseRetracted` | RetractRelease | External: EYG hub (retraction notice) | PackageRelease | Whenever ReleaseRetracted for a pinned release, alert the workspace. Never unpin automatically, since replays still need the CID; new runs refuse it unless the pin is explicitly confirmed |
| `SignatoryRevoked` | RevokeSignatory (with compromised-since time; no approval needed) | Admin, or a hub key revocation notice | TrustStore | Whenever SignatoryRevoked, invalidate ReleaseVerifications signed by that key after compromised-since and flag the runs that executed them in the code exposure view |

Read models:

- Trusted signatories per workspace with scope, approver and status
- Pinned releases with CID, signer, verification status and retraction flag
- Code provenance per run: every module CID, its release, signer and verification event
- Code exposure: runs that executed a retracted release or code signed by a revoked key

## Content store

Blocks by CID: roots that keep them alive, garbage collection, integrity and rebuilds.

| Event | Command | Actor | Aggregate | Policies |
| --- | --- | --- | --- | --- |
| `ContentRootPinned` | PinContentRoot (root CID, holder, reason, until) | Records policy (legal hold), files policy (snapshot tag), Operator (person) | ContentScope |  |
| `ContentRootReleased` | ReleaseContentRoot (root CID, holder) | Records policy (hold released, retention purge), Operator (person) | ContentScope |  |
| `GarbageCollectionSweepCompleted` | SweepUnreachableBlocks (scope, mark epoch, grace period) | Collector schedule (system, nightly per scope) | ContentScope |  |
| `BlockIntegrityFailed` | ReportBlockIntegrityFailure (CID, missing or hash mismatch, where found) | Any block reader: replaying run, scrubber, audit exporter, file reader | ContentScope | Whenever BlockIntegrityFailed, VerifyAuditLog over the range whose events reference that block<br>Whenever BlockIntegrityFailed, RepairBlock from a replica or (public scope) from the hub. If no source verifies, alert the operator and mark the runs whose journals reference the CID as not replayable.<br>Whenever content.BlockIntegrityFailed hits a database snapshot, or the working copy fails its integrity check, RestoreDatabase from the latest verifiable snapshot and replay the statements after it |
| `BlockRepaired` | RepairBlock (CID, source) | External: Replica block store or the hub (public module blocks, verified by CID) | ContentScope |  |
| `ProjectionRebuilt` | RebuildProjection (read model, projector CID, from position or snapshot) | Operator (person) or deploy policy (new projector version) | Projection |  |

Read models:

- LiveRoots: every root keeping blocks alive (explicit pins plus roots referenced by retained events: file heads, run bases, effect result CIDs, artifact versions, deliveries), with holder and reason. Input to garbage collection marking.
- Storage usage per workspace: unique bytes, referenced bytes, dedup ratio, bytes held by legal holds, reclaimable bytes (operators, billing)
- Integrity report: failed CIDs, repair status, affected streams and runs (auditors, operators)
- Projection status: projector CID, position, lag, last rebuild (operators)

## Files

The workspace file system: each event carries the previous and new root CID.

| Event | Command | Actor | Aggregate | Policies |
| --- | --- | --- | --- | --- |
| `FileWritten` | WriteFile / AppendFile (path, content CID, expected root) | Run (WriteFile/AppendFile effect after EffectPassed), Person (web shell upload), seed policy | FileSystem | Whenever FileWritten or FileDeleted on a path a conversation's runs read (by content CID), queue a 'file changed' notice for that conversation's next agent turn (channels.InputQueued) |
| `DirectoryCreated` | MakeDirectory (path, expected root) | Run (MakeDirectory effect), Person (web shell) | FileSystem |  |
| `FileDeleted` | DeleteFile (path, expected root) | Run (DeleteFile effect), Person (web shell) | FileSystem |  |
| `FileRestored` | RestoreFile (path, from root CID) | Person (team member from file history view), Agent run on a person's behalf | FileSystem |  |
| `FileSystemSnapshotTagged` | TagFileSystemSnapshot (root CID, tag) | Person, daily snapshot schedule, policy before WorkspaceSourceChanged | FileSystem | Whenever FileSystemSnapshotTagged, PinContentRoot(root, holder = tag) |
| `FileSystemRestored` | RestoreFileSystem (to root CID or tag) | Admin (person); privilege-widening restores go through access.PrivilegeChangeProposed | FileSystem |  |

Read models:

- File tree at head: path to content CID, size, last writer and run (teams, agents via ReadDirectory)
- File history per path: every version with root, actor chain, run and step, diff to previous (teams, auditors)
- Snapshots and tags with their roots, plus a diff of any two roots (operators, restore UI)
- Files read per conversation (path, content CID read) for change notices

## Channels and agents

Messages in and out of channels, the queue for the agent and its turns. An agent turn is a run.

| Event | Command | Actor | Aggregate | Policies |
| --- | --- | --- | --- | --- |
| `ChannelNamed` | RecordChannelName | Chat connection (channel list or rename event from the platform) | Channel | Whenever ChannelNamed changes a channel's name, re-resolve its channel config and record access.ChannelShellChanged when the shell differs, and post a notice in the channel ('#dev is now #platform, it now runs with the platform shell') |
| `MessageReceived` | RecordInboundMessage | Chat connection (on behalf of the platform author) | Channel | Whenever MessageReceived from a Person (not Bot, not Self) in a channel whose agent is listening, QueueInput in that message's Conversation<br>Whenever MessageReceived or ReactionAdded, MatchTriggers of the channel (triggers) |
| `ReactionAdded` | RecordReaction | Chat connection (on behalf of the person who reacted) | Channel |  |
| `MessageRetractedOnPlatform` | RecordRetraction | External: Slack / Discord / WhatsApp message deleted or edited event | Channel | Whenever MessageRetractedOnPlatform and the workspace erases retracted messages, RequestErasure of that message's payload (records) |
| `InputQueued` | QueueInput | Person posting / schedule / trigger script that observes | Conversation | Whenever InputQueued and no turn is in progress in the Conversation, StartAgentTurn, which starts a run (runs.RunStarted) as the channel agent |
| `AgentTurnStarted` | StartAgentTurn | Channel agent | Conversation |  |
| `AgentRanProgram` | RecordProgramRun (the agent's run tool) |  | Conversation |  |
| `SubagentDelegated` | Delegate (effect) |  | Conversation |  |
| `MessagePosted` | Post (effect), recorded by RecordPostedMessage | Agent, subagent, trigger script, schedule or bound person (from the run's actor chain) | Channel |  |
| `AgentStayedQuiet` | CompleteAgentTurn (no post) |  | Conversation |  |
| `AgentTurnCompleted` | CompleteAgentTurn |  | Conversation |  |
| `ConversationRestarted` | RestartConversation (/new) | Person in the conversation | Conversation | Whenever channels.ConversationRestarted, CancelRun for the conversation's active turn run and its children<br>Whenever ConversationRestarted, cancel the turn in progress (runs.RunCancelled) and discard results that arrive for the old epoch, but keep reminders, which follow the thread (O9) |
| `ChannelHistoryOpened` | OpenChannelHistory | Admin or auditor who is not a member of the channel | Channel |  |

Read models:

- Channel Activity: team-visible events as sentences ('Bob added the regressions trigger from the product page', 'the agent was stopped from reading secrets'), with Undo only where it exists
- Agent context: the current epoch's last 200 messages of a Conversation, the agent's history
- Why did the bot post this? Each MessagePosted linked to its run, the trigger, schedule or message that caused it, and the shell that allowed it
- Agents at work (operators): turns in progress, queue depth and oldest waiting input per Conversation
- Channel directory per workspace: platform id, current and past names, the config and shell that apply, members as reported by the platform
- Who read this channel (auditors): every ChannelHistoryOpened and every Bind into the channel

## Runs (the journal)

One stream per run: what it was based on, every effect decision and result, suspensions and outcome.

| Event | Command | Actor | Aggregate | Policies |
| --- | --- | --- | --- | --- |
| `RunStarted` | StartRun | Agent turn (session starting a turn run)<br>Trigger policy<br>Schedule policy<br>Person invoking code in a chat or bound web shell | Run | Whenever RunStarted, pin the run's basis and payload blocks as a content root (content.ContentRootPinned)<br>Whenever runs.RunStarted with a parent agent turn, record AgentRanProgram in that turn's Conversation, linking the run |
| `RunBasisPinned` | PinRunBasis (source CID, @name->CID map, interpreter version, shell CID) |  | Run | Whenever RunBasisPinned, VerifyRelease for each release CID in the basis not yet verified under the current trust store version, before the first step is evaluated |
| `EffectInputRewrittenByGate` | DecideEffect |  | Run |  |
| `EffectPassed` | DecideEffect (evaluate the pure gate of the shell in force) | Runtime (interpreter on the machine holding the lease) | Run | Whenever EffectPassed for an internal effect (files, triggers, schedules, artifacts, databases), send the target aggregate's command carrying (run, step) as idempotency key, then RecordEffectResult with what it returns; a repeat returns the original result<br>Whenever EffectPassed for Post, post with run+step in the platform metadata, then record channels.MessagePosted and RecordEffectResult<br>Whenever EffectPassed for a Fetch whose request carries a secret handle, InjectSecret with the current version<br>Whenever runs.EffectPassed for Delegate, record SubagentDelegated and start the child run with the subagent's task |
| `EffectMocked` | DecideEffect |  | Run |  |
| `EffectDenied` | DecideEffect |  | Run | Whenever EffectDenied or EffectMocked for a configuration-API effect (set_user_shell, set_workspace_source, set_secret, delete_secret) and the actor is an agent, trigger or schedule, alert workspace admins of an attempted escalation |
| `GateFailed` | DecideEffect |  | Run |  |
| `EffectResultRecorded` | RecordEffectResult | Runtime (interpreter on the machine holding the lease) | Run | Whenever any decision or result is recorded, project a trace span (OTLP export is a view, never the record)<br>Whenever runs.EffectResultRecorded for Post, record MessagePosted in the Channel with run, step and platform message id; an in-doubt Post is shown in the channel's Activity with Retry and 'It was posted' buttons |
| `LocalEffectResultsRecorded` | FlushLocalResults (Now, Random, Flip, lazy pins) |  | Run |  |
| `EffectFailed` | RecordEffectFailure | External: HTTP services (Fetch) | Run |  |
| `EffectRetryScheduled` | ScheduleEffectRetry (same idempotency key, backoff) |  | Run | Whenever EffectRetryScheduled, ResumeRun at the retry time and perform the effect again with the same key |
| `EffectOutcomeInDoubt` | MarkEffectInDoubt |  | Run | Whenever EffectOutcomeInDoubt, post a notice to the run's channel and add it to the in doubt queue, the run stays suspended |
| `EffectReconciled` | ReconcileEffect (sent / not sent / retry) | Reconciler (automatic for keyed effects)<br>Person in the channel or admin (unsafe effects) | Run |  |
| `RunSuspended` | SuspendRun (wake_at, awaiting child, awaiting reconciliation) |  | Run | Whenever RunSuspended with wake_at (Sleep), the wake-up queue issues ResumeRun at wake_at on any machine<br>Whenever RunSuspended or a run ends, ReleaseRunLease and free its admission slot; the next queued run is admitted |
| `ChildRunAwaited` | AwaitChildRun (child id = hash(parent run, step)) | Parent run (Delegate, Dataclip, agent run tool) | Run | Whenever ChildRunAwaited, StartRun for the child with the derived id (a second start is a no-op)<br>Whenever ChildRunAwaited, the parent's slot is lent to the child (no new slot for a sequential child) |
| `RunResumed` | ResumeRun (replay journal, then go live) |  | Run | Whenever ResumeRun finds a last EffectPassed with no result: internal or idempotent -> perform again; keyed -> ReconcileEffect via the platform; unsafe -> MarkEffectInDoubt |
| `RunResumedUnderNewShell` | ResumeRun (shell CID in force differs from the last decision) |  | Run |  |
| `ReplayDiverged` | ResumeRun (replay asked for a different effect than recorded) | Replayer on the new lease holder | Run |  |
| `RunCheckpointed` | CheckpointRun (at a suspension point) |  | Run |  |
| `RunCompleted` | CompleteRun |  | Run | Whenever a child's RunCompleted or RunFailed, ResumeRun of the parent with the child's outcome as the effect result<br>Whenever RunCompleted, RunFailed or RunCancelled, release the run's content root once retention and holds allow (content.ContentRootReleased)<br>Whenever runs.RunCompleted, RunFailed or RunCancelled for a turn's run, CompleteAgentTurn, then start the next queued input |
| `RunFailed` | FailRun |  | Run | Whenever a run caused by a trigger ends in RunFailed, RecordTriggerScriptFailure |
| `RunCancelled` | CancelRun | Admin (person) | Run |  |

Read models:

- Run timeline: every decision with shell CID, rewritten inputs, results, mocks clearly marked, actor chain (auditors, developers)
- In doubt effects queue with the reconcile choices (people, operators)
- Live and suspended runs per workspace and channel, with reason and wake time (operators)
- Run tree: parent, children, cause and on_behalf_of chain (auditors)
- Mocked and denied effects per shell CID (security reviewing what agents tried)
- Trace spans projected from the journal (observability)

## Fleet

Machines, leases on runs and admission. Coordination, not evidence.

| Event | Command | Actor | Aggregate | Policies |
| --- | --- | --- | --- | --- |
| `MachineJoined` | JoinFleet | Machine (worker node on start) | Machine |  |
| `RunLeaseAcquired` | AcquireRunLease |  | RunLease |  |
| `RunThrottled` | AdmitRun (queue when over the limit) | Run starter (any policy that issues StartRun or ResumeRun) | Admission | Whenever the workspace admission queue passes its bound, pause ingestion: pollers stop advancing PollCursorAdvanced, webhooks answer 503 with Retry-After (connections) |
| `RunLeaseReleased` | ReleaseRunLease (suspension, drain, terminal run) |  | RunLease |  |
| `RunLeaseExpired` | ExpireRunLease | Lease sweeper (clock) | RunLease | Whenever RunLeaseExpired, a live machine with free slots issues AcquireRunLease then ResumeRun (runs) |
| `MachineDrained` | DrainMachine | Operator (deploy, scale down) | Machine | Whenever DrainMachine starts, suspend each of its runs at the next effect boundary and ReleaseRunLease, then MachineDrained |

Read models:

- Machine roster with leases held and slots used (operators)
- Admission queue depth and wait time per workspace, channel and cause (operators, teams wondering why a trigger is slow)
- Wake-up queue: suspended runs by wake_at and retry time (drives ResumeRun)

## Triggers

Configured and runtime triggers per channel, both durable, configuration wins a name clash.

| Event | Command | Actor | Aggregate | Policies |
| --- | --- | --- | --- | --- |
| `TriggerAdded` | AddTrigger (AddTrigger effect keyed by run+step, or a product page card) | Agent program (AddTrigger, StopTrigger, StartTrigger, DeleteTrigger effects)<br>Person on the product page (trigger card) | ChannelTriggers |  |
| `TriggerReplaced` | ReplaceTrigger (explicit, same name, new definition) |  | ChannelTriggers |  |
| `TriggerSavedToWorkspace` | SaveTriggerToWorkspace | Person promoting a runtime trigger into workspace.eyg | ChannelTriggers | Whenever TriggerSavedToWorkspace, propose the source change (configuration.WorkspaceSourceChanged); after it is applied the runtime copy is shadowed |
| `TriggerShadowedByConfiguration` | ShadowTrigger |  | ChannelTriggers |  |
| `TriggerMatched` | MatchEvent (pure patterns of active triggers) | Matcher (policy on every delivery) | ChannelTriggers | Whenever TriggerMatched, StartRun with id = hash(trigger definition CID, event id), through admission; a duplicate delivery starts nothing |
| `TriggerScriptFailed` | RecordTriggerScriptFailure |  | ChannelTriggers | Whenever TriggerScriptFailed 5 times in a row, StopTrigger and post why to the channel |
| `TriggerStopped` | StopTrigger | Circuit breaker (policy) | ChannelTriggers |  |
| `TriggerResumed` | ResumeTrigger |  | ChannelTriggers |  |
| `TriggerDeleted` | DeleteTrigger |  | ChannelTriggers |  |

Read models:

- Triggers per channel: configured or runtime, active or stopped, shadowed, last match, consecutive failures (teams, product page)
- Match history: delivery -> trigger -> run -> outcome (auditors, debugging)

## Connections

Chats and services connected to a workspace, and every delivery they make.

| Event | Command | Actor | Aggregate | Policies |
| --- | --- | --- | --- | --- |
| `ChatConnected` | ConnectConnection | External: Slack / Discord / WhatsApp / example chat | Connection |  |
| `ServiceConnected` | ConnectConnection | Configuration reconciler, on behalf of the person whose WorkspaceSourceChanged added the connection | Connection | Whenever ServiceConnected for a polling source, PollConnection once as backfill: events are logged, not live, and run no triggers |
| `UnauthenticatedConnectionCreated` | AcknowledgeUnauthenticatedWebhook | Person who saved workspace.eyg with a webhook without a secret | Connection | Whenever UnauthenticatedConnectionCreated, add it to the exposure view and remind admins weekly until a secret is set<br>Whenever UnauthenticatedConnectionCreated, flag the connection in the admin page and the product page cards, and post once in its channel ('anyone with the URL can send events to #dev') |
| `ConnectionBackfilled` | PollConnection (first poll) | Poller | Connection |  |
| `WebhookDeliveryAuthenticated` | AcceptWebhookDelivery | External sender (GitHub, Sentry, log drain) | DeliveryInbox | Whenever WebhookDeliveryAuthenticated, RecordConnectionEvent for each event in it (one for each array element with split) |
| `WebhookDeliveryRejected` | AcceptWebhookDelivery (signature invalid or missing) |  | DeliveryInbox | Whenever WebhookDeliveryRejected happens 5 times in an hour for one connection, post one notice in its channel and show the reason on the connection, because 'my webhook does nothing' is the usual setup problem |
| `WebhookReplayDetected` | AcceptWebhookDelivery (delivery id already seen) |  | DeliveryInbox |  |
| `ConnectionEventReceived` | RecordConnectionEvent | Poller or webhook listener | DeliveryInbox | Whenever connections.ConnectionEventReceived or channels.MessageReceived, MatchEvent against active triggers of the channel<br>Whenever connections.ConnectionEventReceived from a chat connection, RecordInboundMessage or RecordReaction in the Channel (deduplicated by platform message id)<br>Whenever ConnectionEventReceived is live and the connection names a channel, MatchTriggers of that channel (triggers.TriggerMatched) |
| `PollCursorAdvanced` | AdvanceCursor (after a poll) | Poller | Connection |  |
| `ServiceDisconnected` | DisconnectConnection | Configuration reconciler, on behalf of the person who removed the connection or deleted its secret | Connection | Whenever ServiceDisconnected (chat or service), DeleteSecret for that connection's credentials<br>Whenever ServiceDisconnected, post once in the channel it fed ('github no longer sends events to #dev, the GITHUB_WEBHOOK_SECRET was deleted by Alice') |

Read models:

- Connections page per workspace: name, kind, channel, status (live, backfilling, unauthenticated, disconnected), last delivery and rejected count. It also gives the product page cards their '✓ github sends events to #dev'
- Connection event log: the latest events of a connection, newest first, which is the Events effect's answer
- Delivery debugger (team setting up a webhook): the last 50 deliveries with accepted, rejected or replayed and the reason, plus which triggers matched
- Volume per connection per hour: received, matched, rejected, for operators and retention

## Schedules

Reminders and recurring schedules that message a session. Sleep is a run suspension, not a schedule.

| Event | Command | Actor | Aggregate | Policies |
| --- | --- | --- | --- | --- |
| `ReminderSet` | SetReminder (Timeout effect, keyed by run+step) | Agent program (Timeout, Cron, CancelSchedule effects) | ScheduleBook |  |
| `RecurringScheduleSet` | SetRecurringSchedule (Cron effect or configured cron) | Configuration policy (configured crons) | ScheduleBook |  |
| `ScheduleOccurrenceFired` | FireOccurrence (schedule id + due instant) | Scheduler (leased, one per workspace) | ScheduleBook | Whenever ScheduleOccurrenceFired, queue its message in the target conversation (channels.InputQueued), idempotent on the occurrence id<br>Whenever a reminder's occurrence fired, the reminder is done: no separate cancel event<br>Whenever schedules.ScheduleOccurrenceFired, QueueInput in the schedule's Conversation with the schedule's message |
| `CronOccurrenceMissed` | RecordMissedOccurrences (catch up policy of the schedule) | Scheduler on start after downtime | ScheduleBook |  |
| `ScheduleCancelled` | CancelSchedule |  | ScheduleBook |  |

Read models:

- Upcoming reminders and schedules per channel with next due time and who set them (teams)
- Missed and late occurrences after downtime (operators)

## Artifacts

Versioned bundles stored as UnixFS roots, owned by a channel.

| Event | Command | Actor | Aggregate | Policies |
| --- | --- | --- | --- | --- |
| `ArtifactVersionSaved` | SaveArtifact (Artifact effect) | Agent, trigger script or person bound to a channel, acting as that channel | Artifact | Whenever ArtifactVersionSaved, pin the bundle's root (content.ContentRootPinned), so every published version stays viewable |
| `ArtifactSharedForEditing` | ShareArtifact (effect) | The owner channel's agent, or a person bound to it | Artifact |  |
| `ArtifactUnsharedForEditing` | UnshareArtifact (new effect, the inverse of ShareArtifact) |  | Artifact |  |
| `ArtifactVisibilityChanged` | SetArtifactVisibility (workspace members, anyone with the link) | The owner channel's agent or a person bound to it; making an artifact public is a PrivilegeChangeProposed when the channel shell requires approval | Artifact |  |

Read models:

- Artifact gallery per workspace: name, owner channel, editors, visibility, latest version, saved by and when
- Artifact version history: version, root CID, saved by (actor chain), the run that saved it, the paths that changed
- Served artifacts: name and version to root CID and visibility, read by the HTTP server for /artifacts/<name>/v/<n>/

## Databases and dataclips

Named SQLite databases and the dataclips that read them.

| Event | Command | Actor | Aggregate | Policies |
| --- | --- | --- | --- | --- |
| `DatabaseStatementExecuted` | ExecuteStatement (database, SQL, parameters CID, run, step) | Run with a with_databases shell (SQLite effect), dataclip child run, records erasure policy | Database | Whenever DatabaseStatementExecuted brings the count since the last snapshot to N (default 10,000) or M bytes, TakeDatabaseSnapshot |
| `DatabaseSnapshotTaken` | TakeDatabaseSnapshot (database, at sequence) | Snapshot policy (every N statements or M bytes, nightly), Admin | Database | Whenever DatabaseSnapshotTaken, statements older than the previous snapshot fall to the database retention class (records), and the snapshot root is referenced by the event so LiveRoots keeps it |
| `DatabaseRestored` | RestoreDatabase (database, to snapshot or sequence) | Admin (person), recovery policy after a corrupt working copy | Database |  |
| `DataclipInvoked` | InvokeDataclip (name, arguments CID) | Run in a channel with the dataclips shell (agent turn, trigger script), Person via web shell | Dataclip |  |

Read models:

- Database catalog: name, sequence, size, last statement and actor, last snapshot, statements since snapshot (operators, admins)
- Statement log per database with actor chain, run/step and shell CID; parameters decryptable by auditors with the key (auditors)
- Point-in-time database: a read-only copy materialised from snapshot plus statements to sequence S (auditors, restore preview)
- Dataclip usage: who asked which dataclip, under which shell, with result CID (teams, security)

## Evidence

The hash chained global ledger: checkpoints, verification, export and the upcasters used to read it.

| Event | Command | Actor | Aggregate | Policies |
| --- | --- | --- | --- | --- |
| `AuditLogCheckpointSigned` | SignCheckpoint {global_position, chain_head_hash, previous_checkpoint_hash, key_id} | Checkpointer (system scheduler) | CheckpointChain | Every 1000 ledger events or 5 minutes, whichever comes first, SignCheckpoint<br>Whenever AuditLogCheckpointSigned, AnchorCheckpoint to every configured anchor. An anchor still missing after 1 hour raises an operator alert |
| `CheckpointAnchored` | AnchorCheckpoint {checkpoint_hash, anchor} | Checkpointer (system) | CheckpointChain |  |
| `AuditLogVerified` | VerifyAuditLog {from_position, to_position, against_checkpoint} | Independent verifier (auditor's process run outside the cloud, reads the export API and the anchors)<br>Daily verification job (system) | CheckpointChain | Daily, VerifyAuditLog from the last verified position to the latest anchored checkpoint |
| `AuditLogTamperDetected` | VerifyAuditLog (failed) | Independent verifier or verification job | CheckpointChain | Whenever AuditLogTamperDetected, PlaceLegalHold over the whole cloud (preservation hold, records), suspend retention purges and post an alert to admins and auditors (channels). Keep signing checkpoints so the damage stays bounded |
| `TamperIncidentResolved` | ResolveTamperIncident {incident, finding, evidence_cid} | Auditor (person) together with the cloud operator (two people) | CheckpointChain |  |
| `AuditTrailExported` | ExportAuditTrail {scope, from, to, recipient, legal_basis, format} | Auditor (person, audit shell) | AuditExport |  |
| `EventUpcasterRegistered` | RegisterEventUpcaster {event_type, from_version, to_version, upcaster_cid, test_vectors_cid} | Platform developer (person), approved by a second person | UpcasterRegistry | Whenever EventUpcasterRegistered, RebuildProjection for every view that reads that event type (content)<br>Whenever evidence.EventUpcasterRegistered, RebuildProjection for every read model that consumes that event type |
| `CheckpointKeyRotated` | RotateCheckpointKey {new_key_id, public_key, signed_by_old_key} | Cloud operator (person), approved by an auditor | CheckpointChain |  |

Read models:

- Ledger health: last checkpoint, last anchor per anchor, last verified position, gap since then, open tamper incidents
- Who did what: events by actor and by any person in the on_behalf_of chain, with causation tree (person -> agent turn -> subagent -> trigger -> run)
- Decision evidence per agent, channel or shell CID: attempted effects, passed, rewritten, mocked, denied and gate failures over a period
- Export register: every export, its scope, recipient, legal basis and the checkpoint it was verified against
- Upcaster catalogue: event type versions and the upcaster CID that maps each

## Records management

Retention, legal holds and erasure, a governed process with deadlines.

| Event | Command | Actor | Aggregate | Policies |
| --- | --- | --- | --- | --- |
| `RetentionPolicySet` | SetRetentionPolicy {category, period, legal_basis} | Records officer (person). A shortening needs a second person's approval | RetentionSchedule | Daily, for each category, PurgeExpiredRecords for payloads older than the period that no active hold covers. Envelopes are never purged, only their payload roots are released |
| `RetentionPurgeCompleted` | PurgeExpiredRecords {category, up_to_position, roots_released} | Retention job (system scheduler) | RetentionSchedule | Whenever RetentionPurgeCompleted, ReleaseContentRoot for each released root and then run a garbage collection sweep (content) |
| `LegalHoldPlaced` | PlaceLegalHold {matter, scope: workspace\|channel\|subject\|time range, reason} | Legal counsel or records officer (person)<br>Tamper response policy (system, preservation hold) | LegalHold | Whenever LegalHoldPlaced, PinContentRoot for the payload roots in scope (content), so neither a purge nor garbage collection can remove them<br>Whenever records.LegalHoldPlaced, PinContentRoot for every payload root referenced by the held streams (holder = the hold id) |
| `LegalHoldReleased` | ReleaseLegalHold {hold, reason} | Legal counsel (person), approved by a second person | LegalHold | Whenever LegalHoldReleased, ReleaseContentRoot for the hold's pins, then re-evaluate refused erasure requests whose subject is no longer under any hold<br>Whenever records.LegalHoldReleased, ReleaseContentRoot for that hold's pins |
| `ErasureRequested` | RequestErasure {subject, scope, received_at, channel_of_request} | Data subject (person), lodged by a privacy officer or self-service | DataSubject | Whenever ErasureRequested, if any active hold covers the subject, RefuseErasure; otherwise ShredSubjectKey once the request is approved and before the legal deadline<br>Whenever records.ErasureRequested covers a conversation, CancelSchedule for reminders targeting it (their message text is personal data)<br>Whenever ErasureRequested for a person, DeactivatePerson first. After SubjectKeyShredded their grants stay in history under a pseudonymous person id<br>Whenever records.ErasureRequested covers content in an artifact version, hide that version with a note and keep the version number, never renumber<br>Whenever records.ErasureRequested for a subject, run the workspace's configured erasure dataclip for that subject (DELETE/UPDATE statements), then TakeDatabaseSnapshot. Only after that may records shred the subject key and release older snapshots that contain the subject. |
| `ErasureRefusedUnderLegalHold` | RefuseErasure {request, holds} | Erasure process (system policy) | DataSubject |  |
| `SubjectKeyShredded` | ShredSubjectKey {subject, key_version} | Privacy officer (person) approving the erasure process | DataSubject | Whenever SubjectKeyShredded, RebuildProjection for views that cached decrypted payloads (content) and rebuild databases derived from the subject's events (databases). Channel histories show the messages as erased<br>Whenever records.RetentionPurgeCompleted or records.SubjectKeyShredded, SweepUnreachableBlocks for that scope at the next window |

Read models:

- Retention schedule per workspace: category, period, legal basis, next purge, volume due
- Active legal holds by scope, and which subjects, channels and roots each one freezes
- Erasure cases: request date, deadline, status (pending, refused under hold, shredded), holds blocking
- Disposition log: what was purged or shredded, when, under which policy version or request (what a regulator asks for)
