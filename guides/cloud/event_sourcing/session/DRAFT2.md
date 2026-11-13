# Facilitator's draft timeline (stage 2)

## Identity and access (`identity`)
Who people are, how they sign in, which shell each person runs with.

- `identity.CloudBootstrapped`
- `identity.PersonInvited`
- `identity.PersonSignedUp`  (merged: UserRegistered)
- `identity.PersonSignedIn`  (merged: UserSignedIn)
- `identity.SignInRejected`
- `identity.SessionTokenRevoked`
- `identity.AdminGranted`  (merged: AdminRoleGranted)
- `identity.AdminRevoked`
- `identity.ShellAssignmentRequested`
- `identity.PersonShellAssigned`  (merged: UserShellAssigned, ShellGiven, UserShellChanged)
- `identity.WebShellBoundToChannel`  (merged: ChannelBound)

## Workspace configuration and policy (`configuration`)
workspace.eyg and cloud.eyg versions, the shells they define and when a version takes effect.

- `configuration.WorkspaceCreated`
- `configuration.WorkspaceSourceChanged`  (merged: WorkspaceConfigurationChanged)
- `configuration.WorkspaceConfigurationEvaluated`
- `configuration.WorkspaceConfigurationRejected`
- `configuration.ShellDefinitionPublished`  (merged: ShellDefinitionChanged)
- `configuration.ChannelShellChanged`
- `configuration.WorkspaceConfigurationReverted`

## Secrets (`secrets`)
Secret values never appear in events, only that they were set, read or injected.

- `secrets.SecretSet`  (merged: SecretSaved, SecretStored)
- `secrets.SecretRotated`  (merged: ConnectionCredentialRotated)
- `secrets.SecretReadByConfiguration`
- `secrets.SecretInjectedIntoRequest`  (merged: SecretInjectedForHost)
- `secrets.SecretInjectionRefused`
- `secrets.SecretDeleted`

## Code by hash (`packages`)
Modules and packages are content addressed, @name is resolved to a hash once and pinned.

- `packages.ModulePublished`
- `packages.ReleaseSigned`
- `packages.PackageNameResolved`  (merged: PackageReferenceResolved, PackageVersionResolved)
- `packages.PackageSignatureVerified`
- `packages.PackageVerificationFailed`
- `packages.PackagePinned`  (merged: PackageVersionPinned)

## Content store and file system (`storage`)
Blocks stored once by CID, the shared file system as a sequence of roots.

- `storage.BlockStored`
- `storage.FileWritten`
- `storage.FileDeleted`
- `storage.FileSystemRootAdvanced`  (merged: FileTreeCommitted, FileTreeRootChanged)
- `storage.FileSystemSnapshotTagged`
- `storage.FileSystemRestored`
- `storage.BlockPinned`
- `storage.BlockUnpinned`
- `storage.GarbageCollectionSweepCompleted`
- `storage.BlockFoundMissing`

## Conversations and agents (`conversations`)
Messages in channels, the agent's turns and its history.

- `conversations.MessagePosted`  (merged: SessionMessageAppended)
- `conversations.ReactionAdded`
- `conversations.AgentTurnStarted`
- `conversations.ModelResponseReceived`  (merged: CompletionReceived)
- `conversations.ToolCallExecuted`
- `conversations.SubagentDelegated`  (merged: SubagentAsked, AgentDelegatedSubagent)
- `conversations.AgentReplied`
- `conversations.AgentStayedQuiet`
- `conversations.AgentTurnCompleted`  (merged: AgentTurnFinished)
- `conversations.ConversationRestarted`  (merged: SessionReset, SessionHistoryReset)

## Program runs and durable execution (`runs`)
A run of an EYG program and its journal: every effect is requested, decided, and its result recorded before the run resumes.

- `runs.InputQueued`
- `runs.RunStarted`  (merged: ProgramRunStarted)
- `runs.ReferencesPinned`
- `runs.RunLeaseAcquired`
- `runs.EffectRequested`
- `runs.EffectPermitted`  (merged: EffectAllowed, EffectPassed, PolicyDecided, EffectDecisionMade, EffectInputRewrittenByGate)
- `runs.EffectMocked`
- `runs.EffectDenied`  (merged: EffectBlocked)
- `runs.GateFailed`  (merged: PolicyGateFailed)
- `runs.EffectResultRecorded`
- `runs.EffectFailed`
- `runs.EffectOutcomeInDoubt`
- `runs.EffectReconciled`
- `runs.RunSuspended`
- `runs.RunLeaseRenewed`
- `runs.RunLeaseExpired`
- `runs.RunResumed`  (merged: ProgramRunResumed, ProgramResumedAfterRestart, ProgramRunResumedOnAnotherNode, ProgramReplayedOnNewNode, RunReplayed)
- `runs.ReplayDiverged`
- `runs.RunCheckpointed`  (merged: ProgramRunCheckpointed)
- `runs.RunThrottled`
- `runs.RunCompleted`  (merged: ProgramRunCompleted)
- `runs.RunFailed`
- `runs.RunCancelled`
- `runs.MachineJoined`
- `runs.MachineDrained`

## Triggers (`triggers`)
Patterns over events that start runs in a channel.

- `triggers.TriggerAdded`  (merged: TriggerAddedAtRuntime)
- `triggers.TriggerSavedToWorkspace`
- `triggers.TriggerMatched`
- `triggers.TriggerScriptFailed`
- `triggers.TriggerStopped`
- `triggers.TriggerDeleted`

## Connections and ingestion (`connections`)
Chats and services connected to a workspace, and the events they deliver.

- `connections.ServiceConnected`  (merged: ChatConnected)
- `connections.UnauthenticatedConnectionCreated`
- `connections.ConnectionBackfilled`  (merged: BackfillLogged, ConnectionBackfillCompleted)
- `connections.WebhookDeliveryAuthenticated`
- `connections.WebhookDeliveryRejected`  (merged: WebhookRejected)
- `connections.WebhookDeliveryReplayed`
- `connections.ConnectionEventReceived`  (merged: ConnectionEventIngested)
- `connections.PollCursorAdvanced`

## Schedules (`schedules`)
Crons and timeouts that send messages to sessions.

- `schedules.ScheduleRegistered`  (merged: CronScheduled, RecurringScheduleSet, ReminderScheduled, TimerArmed)
- `schedules.ScheduleFired`  (merged: CronOccurrenceDue, TimerFired)
- `schedules.CronOccurrenceMissed`
- `schedules.ScheduleCancelled`

## Artifacts, databases and dataclips (`outputs`)
What programs produce and share: artifact versions, database changes, dataclip answers.

- `outputs.ArtifactVersionSaved`  (merged: ArtifactPublished)
- `outputs.ArtifactShared`
- `outputs.DatabaseStatementExecuted`  (merged: DatabaseWriteCommitted)
- `outputs.DatabaseSnapshotTaken`
- `outputs.DataclipInvoked`  (merged: DataclipAsked)

## Audit and compliance (`audit`)
The log itself: sealing, verification, retention, holds, erasure and export.

- `audit.AuditLogCheckpointSigned`  (merged: AuditLogSealed)
- `audit.AuditLogTamperDetected`
- `audit.RetentionPolicyApplied`
- `audit.LegalHoldPlaced`
- `audit.PersonalDataErased`  (merged: FileContentErased)
- `audit.AuditTrailExported`
- `audit.ProjectionRebuilt`
- `audit.EventSchemaUpcasted`

## Dropped
- ActorIdentified: an actor is metadata on every event, not an event
- AuditEventAppended: every event is appended, the log does not log itself

## Hot spots
- H1 [runs] Decision shape: are EffectPermitted, EffectMocked and EffectDenied separate events, or one EffectDecided with a decision field? Either way the event must carry the shell's CID and, when a gate rewrote the input, both inputs.
- H2 [runs] Replay semantics: after a crash, does a resumed run reuse recorded decisions, or re-check the current shell? What if a permission was revoked in between?
- H3 [runs] Effects whose outcome is unknown after a crash (a Post that may have been sent): retry, reconcile with the platform, or ask a person?
- H4 [runs] Journal cost on the hot path: is every Now, Random and ReadFile journaled, and is each result fsynced before resuming?
- H5 [runs] Mocked results must never be mistaken for real ones in audit or replay.
- H6 [audit] Erasure versus immutability: personal data in messages, files and effect results. Crypto-shredding with per subject keys, or keep personal data out of events entirely?
- H7 [audit] Stream layout and order: one stream per aggregate plus a global position, whose clock is authoritative, and how is the global order hash chained?
- H8 [audit] Schema evolution: upcasting on read rather than rewriting history, so hash chains stay valid.
- H9 [audit] Tracing is sampled and in memory, it cannot be the audit record.
- H10 [secrets] Effect inputs and results can contain secrets (SetSecret's value, an Env answer, a fetched token). What is redacted before recording, and how is a replay fed without the secret?
- H11 [packages] @name resolves to the latest version: every run must pin the hashes it resolved, so a replay runs the same code.
- H12 [storage] Payloads inline or as blobs: effect results, model responses and files go to the block store by CID; which roots keep blocks alive for garbage collection?
- H13 [identity] Who is the actor? A person, an agent acting for a person, a trigger, a schedule or a connection. Every event needs the chain of on-behalf-of.
- H14 [identity] Sign in today is by name and the first visitor becomes admin. Bootstrap and authentication need explicit events.
- H15 [triggers] Two sources of truth: triggers in workspace.eyg and triggers added at runtime. Which wins, and is a runtime trigger an event or a configuration change?
- H16 [connections] Webhooks without a secret, tokens in URLs and replayed deliveries.
- H17 [connections] Volume: log drains can send thousands of events a minute. Which are recorded, which only matched?
- H18 [outputs] SQLite databases change outside the event log. Are statements events, or are databases projections?
- H19 [schedules] Cron catch-up after downtime: fire missed occurrences, skip them, or fire one?
- H20 [configuration] Undo: a configuration can be reverted, a posted message cannot. What does revert mean for effects already performed?