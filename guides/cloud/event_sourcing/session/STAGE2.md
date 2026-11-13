# Stage 2 timeline

## Identity (`identity`)
Who people and API clients are and how they prove it. Authentication only, grants live in access.

0. `identity.CloudBootstrapped`
1. `identity.PersonInvited`
2. `identity.PersonSignedUp`
3. `identity.PersonSignedIn`
4. `identity.SignInRejected`
5. `identity.ApiCredentialIssued`
6. `identity.CredentialRevoked`
7. `identity.PersonDeactivated`

## Access (`access`)
Who may do what: shell definitions, channel shells, person shells, admin, bindings, and proposals that widen privilege.

0. `access.ShellDefinitionPublished`
1. `access.ChannelShellChanged`
2. `access.PrivilegeChangeProposed`
3. `access.PrivilegeChangeApproved`
4. `access.PrivilegeChangeDeclined`
5. `access.AdminGranted`
6. `access.AdminRevoked`
7. `access.PersonShellAssigned`
8. `access.PersonBoundToChannel`
9. `access.PersonUnboundFromChannel`

## Workspace configuration (`configuration`)
Versions of workspace.eyg by source CID and the moment a version takes effect.

0. `configuration.WorkspaceCreated`
1. `configuration.WorkspaceSourceChanged`
2. `configuration.WorkspaceConfigurationApplied`
3. `configuration.WorkspaceConfigurationRejected`

## Secrets (`secrets`)
Secret values live in a vault, events record names, versions and keyed fingerprints only.

0. `secrets.SecretSet`
1. `secrets.SecretRotated`
2. `secrets.SecretInjectedIntoRequest`
3. `secrets.SecretInjectionRefused`
4. `secrets.SecretLeakRedacted`
5. `secrets.SecretDeleted`

## Code by hash (`packages`)
Signatories, signed releases, verification, and workspaces pinning releases by hash.

0. `packages.SignatoryTrusted`
1. `packages.ModulePublished`
2. `packages.ReleaseSigned`
3. `packages.PackageSignatureVerified`
4. `packages.PackageVerificationFailed`
5. `packages.PackagePinned`
6. `packages.ReleaseRetracted`
7. `packages.SignatoryRevoked`

## Content store (`content`)
Blocks by CID: roots that keep them alive, garbage collection, integrity and rebuilds.

0. `content.ContentRootPinned`
1. `content.ContentRootReleased`
2. `content.GarbageCollectionSweepCompleted`
3. `content.BlockIntegrityFailed`
4. `content.ProjectionRebuilt`

## Files (`files`)
The workspace file system: each event carries the previous and new root CID.

0. `files.FileWritten`
1. `files.DirectoryCreated`
2. `files.FileDeleted`
3. `files.FileRestored`
4. `files.FileSystemSnapshotTagged`
5. `files.FileSystemRestored`

## Channels and agents (`channels`)
Messages in and out of channels, the queue for the agent and its turns. An agent turn is a run.

0. `channels.MessageReceived`
1. `channels.ReactionAdded`
2. `channels.MessageRetractedOnPlatform`
3. `channels.InputQueued`
4. `channels.AgentTurnStarted`
5. `channels.AgentRanProgram`
6. `channels.SubagentDelegated`
7. `channels.MessagePosted`
8. `channels.AgentStayedQuiet`
9. `channels.AgentTurnCompleted`
10. `channels.ConversationRestarted`

## Runs (the journal) (`runs`)
One stream per run: what it was based on, every effect decision and result, suspensions and outcome.

0. `runs.RunStarted`
1. `runs.RunBasisPinned`
2. `runs.EffectInputRewrittenByGate`
3. `runs.EffectPassed`
4. `runs.EffectMocked`
5. `runs.EffectDenied`
6. `runs.GateFailed`
7. `runs.EffectResultRecorded`
8. `runs.LocalEffectResultsRecorded`
9. `runs.EffectFailed`
10. `runs.EffectRetryScheduled`
11. `runs.EffectOutcomeInDoubt`
12. `runs.EffectReconciled`
13. `runs.RunSuspended`
14. `runs.ChildRunAwaited`
15. `runs.RunResumed`
16. `runs.RunResumedUnderNewShell`
17. `runs.ReplayDiverged`
18. `runs.RunCheckpointed`
19. `runs.RunCompleted`
20. `runs.RunFailed`
21. `runs.RunCancelled`

## Fleet (`fleet`)
Machines, leases on runs and admission. Coordination, not evidence.

0. `fleet.MachineJoined`
1. `fleet.RunLeaseAcquired`
2. `fleet.RunThrottled`
3. `fleet.RunLeaseExpired`
4. `fleet.MachineDrained`

## Triggers (`triggers`)
Configured and runtime triggers per channel, both durable, configuration wins a name clash.

0. `triggers.TriggerAdded`
1. `triggers.TriggerSavedToWorkspace`
2. `triggers.TriggerShadowedByConfiguration`
3. `triggers.TriggerMatched`
4. `triggers.TriggerScriptFailed`
5. `triggers.TriggerStopped`
6. `triggers.TriggerResumed`
7. `triggers.TriggerDeleted`

## Connections (`connections`)
Chats and services connected to a workspace, and every delivery they make.

0. `connections.ChatConnected`
1. `connections.ServiceConnected`
2. `connections.UnauthenticatedConnectionCreated`
3. `connections.ConnectionBackfilled`
4. `connections.WebhookDeliveryAuthenticated`
5. `connections.WebhookDeliveryRejected`
6. `connections.WebhookReplayDetected`
7. `connections.ConnectionEventReceived`
8. `connections.PollCursorAdvanced`
9. `connections.ServiceDisconnected`

## Schedules (`schedules`)
Reminders and recurring schedules that message a session. Sleep is a run suspension, not a schedule.

0. `schedules.ReminderSet`
1. `schedules.RecurringScheduleSet`
2. `schedules.ScheduleOccurrenceFired`
3. `schedules.CronOccurrenceMissed`
4. `schedules.ScheduleCancelled`

## Artifacts (`artifacts`)
Versioned bundles stored as UnixFS roots, owned by a channel.

0. `artifacts.ArtifactVersionSaved`
1. `artifacts.ArtifactShared`
2. `artifacts.ArtifactUnshared`

## Databases and dataclips (`databases`)
Named SQLite databases and the dataclips that read them.

0. `databases.DatabaseStatementExecuted`
1. `databases.DatabaseSnapshotTaken`
2. `databases.DataclipInvoked`

## Evidence (`evidence`)
The hash chained global ledger: checkpoints, verification, export and the upcasters used to read it.

0. `evidence.AuditLogCheckpointSigned`
1. `evidence.AuditLogVerified`
2. `evidence.AuditLogTamperDetected`
3. `evidence.AuditTrailExported`
4. `evidence.EventUpcasterRegistered`

## Records management (`records`)
Retention, legal holds and erasure, a governed process with deadlines.

0. `records.RetentionPolicySet`
1. `records.RetentionPurgeCompleted`
2. `records.LegalHoldPlaced`
3. `records.LegalHoldReleased`
4. `records.ErasureRequested`
5. `records.ErasureRefusedUnderLegalHold`
6. `records.SubjectKeyShredded`

## Removed
- AgentReplied: an agent's reply is MessagePosted with an agent actor
- ModelResponseReceived: a model completion is EffectResultRecorded of the Complete effect in the turn's run
- EffectRequested: folded into the decision events, which are the in doubt marker and the fence
- RunLeaseRenewed: heartbeats live in the lease store, not the audit log
- BlockStored: putting a block is idempotent and proven by its CID
- FileSystemRootAdvanced: every file event carries previous and new root
- SecretReadByConfiguration: WorkspaceConfigurationApplied lists the secret names read
- WorkspaceConfigurationReverted: a revert is a WorkspaceSourceChanged that restores an earlier CID
- ShellAssignmentRequested: replaced by PrivilegeChangeProposed, approved or declined
- PackageNameResolved: resolutions are recorded in RunBasisPinned
- PersonalDataErased: split into ErasureRequested, ErasureRefusedUnderLegalHold and SubjectKeyShredded
- EventSchemaUpcasted: upcasting is on read, registering an upcaster is EventUpcasterRegistered

## Resolved hot spots
- [runs] H1 resolved: separate events EffectPassed, EffectMocked, EffectDenied, GateFailed, each with run, step, effect, input digest, shell CID and actor chain. EffectRequested folds into them. A rewrite is EffectInputRewrittenByGate with digests only.
- [runs] H2 resolved: replayed steps reuse recorded decisions and results, new steps are decided by the shell in force now. A changed shell is RunResumedUnderNewShell.
- [runs] H3 resolved: every effect declares a delivery class: pure, internal, idempotent, keyed or unsafe. Unsafe effects are never retried automatically, they become EffectOutcomeInDoubt for reconciliation or a person.
- [runs] H4 resolved: everything that shapes behaviour is journaled. Now, Random, Flip and lazy pins are buffered and flushed as LocalEffectResultsRecorded before the next externally visible effect. ReadFile records content CIDs, not bytes.
- [runs] H5 resolved: EffectMocked is its own event, replay feeds the mock, projections of the world only consume EffectResultRecorded.
- [records] H6 resolved: personal data stays out of envelopes. Payloads are encrypted blocks with workspace and subject keys, erasure shreds the key.
- [evidence] H7 resolved: one stream per aggregate with optimistic appends on expected version, a global position assigned at commit, hash chained, the ledger's commit time is the authoritative when.
- [evidence] H8 resolved: never rewrite events. Pure upcasters by CID applied on read, registering one is an event.
- [evidence] H9 resolved: traces become a projection of the journal and decisions, never the record.
- [secrets] H10 resolved: effects record secret name and version, never values or plain hashes of values. Replay reads the version from the vault.
- [packages] H11 resolved: RunBasisPinned stores the @name to release to CID map as one block, replay never asks the hub.
- [content] H12 resolved: inline up to 4 KiB, larger payloads are blocks, chunked above 256 KiB. Blocks are written before the event that references them.
- [identity] H13 resolved: a mandatory envelope: actor, on_behalf_of chain ending in a person or a configuration version, shell CID, causation and correlation ids.
- [identity] H14 resolved: CloudBootstrapped by a one time code printed by the server, then invitation only. Sign in records the verified provider and subject.
- [triggers] H15 resolved: runtime and configured triggers are both durable, configuration wins a name clash and the runtime one is TriggerShadowedByConfiguration.
- [connections] H16 resolved: a webhook without a secret is an explicit, attributed opt in and flagged in views. Token in URL is deprecated.
- [connections] H17 resolved: every delivery is stored as a block, high volume sources batch them, deliveries that matched are retained with their run.
- [schedules] H19 resolved: each schedule declares a catch up policy, default one late occurrence, the rest recorded as CronOccurrenceMissed.
- [configuration] H20 resolved: a revert is a WorkspaceSourceChanged that restores an earlier CID. Effects already performed stay facts, the UI lists what is not undone.

## Open hot spots
- O1 [databases] are databases rebuildable projections of DatabaseStatementExecuted (Avery, Dana), or the source with a (run, step) idempotency table (Rui)?
- O2 [evidence] who holds the key that signs checkpoints, and where are they anchored outside the operator's control?
- O3 [access] which changes need a second person (four eyes), and can an agent ever approve a PrivilegeChangeProposed?
- O4 [content] dedup scope and legal holds on blocks shared between scopes: dedup per workspace only?
- O5 [runs] continuations cannot be serialised today, so replay cost grows with the journal. Is RunCheckpointed a continue as new?
- O6 [fleet] backpressure limits per workspace and channel, and does a child run take its parent's slot?
- O7 [secrets] the network secret placeholder is an unsalted SHA-256 of the value, and Bearer injection happens without naming the secret.
- O8 [channels] who may read a channel's history: members, admins, bound people, the founders agent?
- O9 [schedules] where does a reminder go after /new or after its conversation is erased?
- O10 [triggers] submitting the same product page card twice: replace or reject?