# Stage 3: the complete board for sign off

138 events in 17 contexts. board3.html / stage3.png show every command, actor, aggregate, policy and read model.

## Identity (`identity`)
Who people and API clients are and how they prove it. Authentication only, grants live in access.

- `identity.CloudBootstrapped` ← BootstrapCloud (one-time code printed by the server)
- `identity.PersonInvited` ← InvitePerson (with proposed shell)
- `identity.PersonSignedUp` ← AcceptInvitation
- `identity.PersonSignedIn` ← SignIn
- `identity.SignInRejected` ← SignIn (rejected: unknown subject, deactivated, bad assertion, throttled)
- `identity.ApiCredentialIssued` ← IssueApiCredential (scoped to a shell no wider than the issuer's)
- `identity.CredentialRevoked` ← RevokeCredential
- `identity.PersonDeactivated` ← DeactivatePerson

Aggregates: **CloudInstallation** `identity/cloud`; **Person** `identity/person/<person id>`; **SignInGuard** `identity/signin/<provider>/<subject digest>`; **Credential** `identity/credential/<credential id>`

## Access (`access`)
Who may do what: shell definitions, channel shells, person shells, admin, bindings, and proposals that widen privilege.

- `access.ShellDefinitionPublished` ← PublishShellDefinitions (from a cloud.eyg version)
- `access.ChannelShellChanged` ← RecordChannelShells (diff of channel shell CIDs)
- `access.PrivilegeChangeProposed` ← ProposePrivilegeChange (carries the exact command to apply and the expected version of its target)
- `access.PrivilegeChangeApproved` ← ApprovePrivilegeChange
- `access.PrivilegeChangeDeclined` ← DeclinePrivilegeChange
- `access.PrivilegeChangeExpired`
- `access.AdminGranted` ← GrantAdmin
- `access.AdminRevoked` ← RevokeAdmin (no approval needed, refused if it would leave no admin)
- `access.PersonShellAssigned` ← AssignPersonShell (the SetUserShell operation)
- `access.PersonBoundToChannel` ← BindToChannel (Bind effect from the web shell)
- `access.PersonUnboundFromChannel` ← UnbindFromChannel

Aggregates: **ShellCatalog** `access/shells`; **ChannelAccess** `access/channel/<workspace>/<channel>`; **PrivilegeChange** `access/proposal/<proposal id>`; **PersonGrants** `access/person/<person id>`

## Workspace configuration (`configuration`)
Versions of workspace.eyg by source CID and the moment a version takes effect.

- `configuration.CloudSourceChanged`
- `configuration.WorkspaceCreated` ← CreateWorkspace
- `configuration.WorkspaceSourceChanged` ← SetWorkspaceSource {workspace, source_cid, expected_previous_cid, reason, restores?}
- `configuration.WorkspaceConfigurationApplied` ← ApplyWorkspaceConfiguration {source_cid, evaluated_config_cid, secret_names_read, basis}
- `configuration.WorkspaceConfigurationRejected` ← RejectWorkspaceConfiguration {source_cid, reason}

Aggregates: **WorkspaceConfiguration** `configuration/<workspace>`

## Secrets (`secrets`)
Secret values live in a vault, events record names, versions and keyed fingerprints only.

- `secrets.SecretSet` ← SetSecret (value goes straight to the vault, the event gets name, version, keyed fingerprint and a fresh opaque handle)
- `secrets.SecretRotated` ← RotateSecret
- `secrets.SecretInjectedIntoRequest` ← InjectSecret (egress replaces the opaque handle for an allowed host)
- `secrets.SecretInjectionRefused` ← InjectSecret (refused: host not allowed, secret deleted, handle from a retired version)
- `secrets.SecretLeakRedacted` ← RedactPayload (scan for known values and handles before EffectResultRecorded, MessagePosted, MessageReceived, FileWritten)
- `secrets.SecretDeleted` ← DeleteSecret (crypto-erases the value in the vault)

Aggregates: **SecretVault** `secrets/<workspace>`; **SecretEgress** `secrets/egress/<run id>`; **LeakRegister** `secrets/leaks/<workspace>`

## Code by hash (`packages`)
Signatories, signed releases, verification, and workspaces pinning releases by hash.

- `packages.SignatoryTrusted` ← TrustSignatory (key fingerprint and name scope, e.g. @acme/*)
- `packages.ModulePublished` ← PublishModule
- `packages.ReleaseSigned` ← SignRelease
- `packages.PackageSignatureVerified` ← VerifyRelease (hash of fetched bytes equals CID, signature by a trusted key in scope, release not retracted)
- `packages.PackageVerificationFailed` ← VerifyRelease (failed: hash mismatch, unknown or revoked signer, out of scope)
- `packages.PackagePinned` ← PinPackage (only a verified release)
- `packages.ReleaseRetracted` ← RetractRelease
- `packages.SignatoryRevoked` ← RevokeSignatory (with compromised-since time; no approval needed)

Aggregates: **TrustStore** `packages/trust/<workspace>`; **PackageRelease** `packages/release/<package name> (mirror of the hub)`; **ReleaseVerification** `packages/verification/<workspace>/<release CID>`; **WorkspacePins** `packages/pins/<workspace>`

## Content store (`content`)
Blocks by CID: roots that keep them alive, garbage collection, integrity and rebuilds.

- `content.ContentRootPinned` ← PinContentRoot (root CID, holder, reason, until)
- `content.ContentRootReleased` ← ReleaseContentRoot (root CID, holder)
- `content.GarbageCollectionSweepCompleted` ← SweepUnreachableBlocks (scope, mark epoch, grace period)
- `content.BlockIntegrityFailed` ← ReportBlockIntegrityFailure (CID, missing or hash mismatch, where found)
- `content.BlockRepaired` ← RepairBlock (CID, source)
- `content.ProjectionRebuilt` ← RebuildProjection (read model, projector CID, from position or snapshot)

Aggregates: **ContentScope** `content/<workspace>|content/public`; **Projection** `projections/<read model>`

## Files (`files`)
The workspace file system: each event carries the previous and new root CID.

- `files.FileWritten` ← WriteFile / AppendFile (path, content CID, expected root)
- `files.DirectoryCreated` ← MakeDirectory (path, expected root)
- `files.FileDeleted` ← DeleteFile (path, expected root)
- `files.FileRestored` ← RestoreFile (path, from root CID)
- `files.FileSystemSnapshotTagged` ← TagFileSystemSnapshot (root CID, tag)
- `files.FileSystemRestored` ← RestoreFileSystem (to root CID or tag)

Aggregates: **FileSystem** `files/<workspace>`

## Channels and agents (`channels`)
Messages in and out of channels, the queue for the agent and its turns. An agent turn is a run.

- `channels.ChannelNamed` ← RecordChannelName
- `channels.MessageReceived` ← RecordInboundMessage
- `channels.ReactionAdded` ← RecordReaction
- `channels.MessageRetractedOnPlatform` ← RecordRetraction
- `channels.InputQueued` ← QueueInput
- `channels.AgentTurnStarted` ← StartAgentTurn
- `channels.AgentRanProgram` ← RecordProgramRun (the agent's run tool)
- `channels.SubagentDelegated` ← Delegate (effect)
- `channels.MessagePosted` ← Post (effect), recorded by RecordPostedMessage
- `channels.AgentStayedQuiet` ← CompleteAgentTurn (no post)
- `channels.AgentTurnCompleted` ← CompleteAgentTurn
- `channels.ConversationRestarted` ← RestartConversation (/new)
- `channels.ChannelHistoryOpened` ← OpenChannelHistory

Aggregates: **Channel** `channels/<workspace>/<platform>:<channel_id>`; **Conversation** `conversations/<workspace>/<platform>:<channel_id>:<thread>`

## Runs (the journal) (`runs`)
One stream per run: what it was based on, every effect decision and result, suspensions and outcome.

- `runs.RunStarted` ← StartRun
- `runs.RunBasisPinned` ← PinRunBasis (source CID, @name->CID map, interpreter version, shell CID)
- `runs.EffectInputRewrittenByGate` ← DecideEffect
- `runs.EffectPassed` ← DecideEffect (evaluate the pure gate of the shell in force)
- `runs.EffectMocked` ← DecideEffect
- `runs.EffectDenied` ← DecideEffect
- `runs.GateFailed` ← DecideEffect
- `runs.EffectResultRecorded` ← RecordEffectResult
- `runs.LocalEffectResultsRecorded` ← FlushLocalResults (Now, Random, Flip, lazy pins)
- `runs.EffectFailed` ← RecordEffectFailure
- `runs.EffectRetryScheduled` ← ScheduleEffectRetry (same idempotency key, backoff)
- `runs.EffectOutcomeInDoubt` ← MarkEffectInDoubt
- `runs.EffectReconciled` ← ReconcileEffect (sent / not sent / retry)
- `runs.RunSuspended` ← SuspendRun (wake_at, awaiting child, awaiting reconciliation)
- `runs.ChildRunAwaited` ← AwaitChildRun (child id = hash(parent run, step))
- `runs.RunResumed` ← ResumeRun (replay journal, then go live)
- `runs.RunResumedUnderNewShell` ← ResumeRun (shell CID in force differs from the last decision)
- `runs.ReplayDiverged` ← ResumeRun (replay asked for a different effect than recorded)
- `runs.RunCheckpointed` ← CheckpointRun (at a suspension point)
- `runs.RunCompleted` ← CompleteRun
- `runs.RunFailed` ← FailRun
- `runs.RunCancelled` ← CancelRun

Aggregates: **Run** `runs/<run_id>, where run_id is derived from the cause: turn = conversation + turn number, trigger = hash(definition CID, event id), occurrence = hash(schedule id, due instant), child = hash(parent run, step), invocation = message id`

## Fleet (`fleet`)
Machines, leases on runs and admission. Coordination, not evidence.

- `fleet.MachineJoined` ← JoinFleet
- `fleet.RunLeaseAcquired` ← AcquireRunLease
- `fleet.RunThrottled` ← AdmitRun (queue when over the limit)
- `fleet.RunLeaseReleased` ← ReleaseRunLease (suspension, drain, terminal run)
- `fleet.RunLeaseExpired` ← ExpireRunLease
- `fleet.MachineDrained` ← DrainMachine

Aggregates: **RunLease** `fleet/leases/<run_id> (in the lease store, coordination not evidence)`; **Machine** `fleet/machines/<machine_id>`; **Admission** `fleet/admission/<workspace>`

## Triggers (`triggers`)
Configured and runtime triggers per channel, both durable, configuration wins a name clash.

- `triggers.TriggerAdded` ← AddTrigger (AddTrigger effect keyed by run+step, or a product page card)
- `triggers.TriggerReplaced` ← ReplaceTrigger (explicit, same name, new definition)
- `triggers.TriggerSavedToWorkspace` ← SaveTriggerToWorkspace
- `triggers.TriggerShadowedByConfiguration` ← ShadowTrigger
- `triggers.TriggerMatched` ← MatchEvent (pure patterns of active triggers)
- `triggers.TriggerScriptFailed` ← RecordTriggerScriptFailure
- `triggers.TriggerStopped` ← StopTrigger
- `triggers.TriggerResumed` ← ResumeTrigger
- `triggers.TriggerDeleted` ← DeleteTrigger

Aggregates: **ChannelTriggers** `triggers/<workspace>/<channel>`

## Connections (`connections`)
Chats and services connected to a workspace, and every delivery they make.

- `connections.ChatConnected` ← ConnectConnection
- `connections.ServiceConnected` ← ConnectConnection
- `connections.UnauthenticatedConnectionCreated` ← AcknowledgeUnauthenticatedWebhook
- `connections.ConnectionBackfilled` ← PollConnection (first poll)
- `connections.WebhookDeliveryAuthenticated` ← AcceptWebhookDelivery
- `connections.WebhookDeliveryRejected` ← AcceptWebhookDelivery (signature invalid or missing)
- `connections.WebhookReplayDetected` ← AcceptWebhookDelivery (delivery id already seen)
- `connections.ConnectionEventReceived` ← RecordConnectionEvent
- `connections.PollCursorAdvanced` ← AdvanceCursor (after a poll)
- `connections.ServiceDisconnected` ← DisconnectConnection

Aggregates: **Connection** `connections/<workspace>/<connection_name>`; **DeliveryInbox** `deliveries/<workspace>/<connection_name>/<yyyy-mm-dd>`

## Schedules (`schedules`)
Reminders and recurring schedules that message a session. Sleep is a run suspension, not a schedule.

- `schedules.ReminderSet` ← SetReminder (Timeout effect, keyed by run+step)
- `schedules.RecurringScheduleSet` ← SetRecurringSchedule (Cron effect or configured cron)
- `schedules.ScheduleOccurrenceFired` ← FireOccurrence (schedule id + due instant)
- `schedules.CronOccurrenceMissed` ← RecordMissedOccurrences (catch up policy of the schedule)
- `schedules.ScheduleCancelled` ← CancelSchedule

Aggregates: **ScheduleBook** `schedules/<workspace>/<conversation> and schedules/<workspace>/configured`

## Artifacts (`artifacts`)
Versioned bundles stored as UnixFS roots, owned by a channel.

- `artifacts.ArtifactVersionSaved` ← SaveArtifact (Artifact effect)
- `artifacts.ArtifactSharedForEditing` ← ShareArtifact (effect)
- `artifacts.ArtifactUnsharedForEditing` ← UnshareArtifact (new effect, the inverse of ShareArtifact)
- `artifacts.ArtifactVisibilityChanged` ← SetArtifactVisibility (workspace members, anyone with the link)

Aggregates: **Artifact** `artifacts/<workspace>/<name>`

## Databases and dataclips (`databases`)
Named SQLite databases and the dataclips that read them.

- `databases.DatabaseStatementExecuted` ← ExecuteStatement (database, SQL, parameters CID, run, step)
- `databases.DatabaseSnapshotTaken` ← TakeDatabaseSnapshot (database, at sequence)
- `databases.DatabaseRestored` ← RestoreDatabase (database, to snapshot or sequence)
- `databases.DataclipInvoked` ← InvokeDataclip (name, arguments CID)

Aggregates: **Database** `databases/<workspace>/<name>`; **Dataclip** `dataclips/<workspace>/<name>`

## Evidence (`evidence`)
The hash chained global ledger: checkpoints, verification, export and the upcasters used to read it.

- `evidence.AuditLogCheckpointSigned` ← SignCheckpoint {global_position, chain_head_hash, previous_checkpoint_hash, key_id}
- `evidence.CheckpointAnchored` ← AnchorCheckpoint {checkpoint_hash, anchor}
- `evidence.AuditLogVerified` ← VerifyAuditLog {from_position, to_position, against_checkpoint}
- `evidence.AuditLogTamperDetected` ← VerifyAuditLog (failed)
- `evidence.TamperIncidentResolved` ← ResolveTamperIncident {incident, finding, evidence_cid}
- `evidence.AuditTrailExported` ← ExportAuditTrail {scope, from, to, recipient, legal_basis, format}
- `evidence.EventUpcasterRegistered` ← RegisterEventUpcaster {event_type, from_version, to_version, upcaster_cid, test_vectors_cid}
- `evidence.CheckpointKeyRotated` ← RotateCheckpointKey {new_key_id, public_key, signed_by_old_key}

Aggregates: **CheckpointChain** `evidence/checkpoints`; **AuditExport** `evidence/exports/<export id>`; **UpcasterRegistry** `evidence/upcasters/<event type>`

## Records management (`records`)
Retention, legal holds and erasure, a governed process with deadlines.

- `records.RetentionPolicySet` ← SetRetentionPolicy {category, period, legal_basis}
- `records.RetentionPurgeCompleted` ← PurgeExpiredRecords {category, up_to_position, roots_released}
- `records.LegalHoldPlaced` ← PlaceLegalHold {matter, scope: workspace|channel|subject|time range, reason}
- `records.LegalHoldReleased` ← ReleaseLegalHold {hold, reason}
- `records.ErasureRequested` ← RequestErasure {subject, scope, received_at, channel_of_request}
- `records.ErasureRefusedUnderLegalHold` ← RefuseErasure {request, holds}
- `records.SubjectKeyShredded` ← ShredSubjectKey {subject, key_version}

Aggregates: **RetentionSchedule** `records/retention/<workspace>`; **LegalHold** `records/holds/<hold id>`; **DataSubject** `records/subjects/<subject id>`

## Hot spot rulings
- H1 resolved: separate events EffectPassed, EffectMocked, EffectDenied, GateFailed, each with run, step, effect, input digest, shell CID and actor chain. EffectRequested folds into them. A rewrite is EffectInputRewrittenByGate with digests only.
- H2 resolved: replayed steps reuse recorded decisions and results, new steps are decided by the shell in force now. A changed shell is RunResumedUnderNewShell.
- H3 resolved: every effect declares a delivery class: pure, internal, idempotent, keyed or unsafe. Unsafe effects are never retried automatically, they become EffectOutcomeInDoubt for reconciliation or a person.
- H4 resolved: everything that shapes behaviour is journaled. Now, Random, Flip and lazy pins are buffered and flushed as LocalEffectResultsRecorded before the next externally visible effect. ReadFile records content CIDs, not bytes.
- H5 resolved: EffectMocked is its own event, replay feeds the mock, projections of the world only consume EffectResultRecorded.
- H6 resolved: personal data stays out of envelopes. Payloads are encrypted blocks with workspace and subject keys, erasure shreds the key.
- H7 resolved: one stream per aggregate with optimistic appends on expected version, a global position assigned at commit, hash chained, the ledger's commit time is the authoritative when.
- H8 resolved: never rewrite events. Pure upcasters by CID applied on read, registering one is an event.
- H9 resolved: traces become a projection of the journal and decisions, never the record.
- H10 resolved: effects record secret name and version, never values or plain hashes of values. Replay reads the version from the vault.
- H11 resolved: RunBasisPinned stores the @name to release to CID map as one block, replay never asks the hub.
- H12 resolved: inline up to 4 KiB, larger payloads are blocks, chunked above 256 KiB. Blocks are written before the event that references them.
- H13 resolved: a mandatory envelope: actor, on_behalf_of chain ending in a person or a configuration version, shell CID, causation and correlation ids.
- H14 resolved: CloudBootstrapped by a one time code printed by the server, then invitation only. Sign in records the verified provider and subject.
- H15 resolved: runtime and configured triggers are both durable, configuration wins a name clash and the runtime one is TriggerShadowedByConfiguration.
- H16 resolved: a webhook without a secret is an explicit, attributed opt in and flagged in views. Token in URL is deprecated.
- H17 resolved: every delivery is stored as a block, high volume sources batch them, deliveries that matched are retained with their run.
- H19 resolved: each schedule declares a catch up policy, default one late occurrence, the rest recorded as CronOccurrenceMissed.
- H20 resolved: a revert is a WorkspaceSourceChanged that restores an earlier CID. Effects already performed stay facts, the UI lists what is not undone.
- O1 resolved (Rui, Dana): the stream databases/<ws>/<name> is the record, the SQLite file a working copy. Each statement commits with a (run, step) row in a cloud owned outbox table, nondeterministic SQL is rejected, snapshots carry a row hash.
- O2 resolved (Avery): a dedicated ledger key in an HSM or keyring, never in the data directory. Checkpoints are anchored to the hub and a public transparency log, CheckpointAnchored, and checked by an independent verifier.
- O3 resolved (Avery, Sam): a second person approves anything that widens privilege or exposure, a shell is narrower only when its gates are a subset by CID. Agents, triggers and schedules may propose, never approve. A single admin may self approve after 24 hours, flagged.
- O4 resolved (Dana): dedup per workspace scope, blocks encrypted with the scope key, only public hub modules are shared. Holds and erasure act on roots and keys, never single blocks.
- O5 resolved (Rui): phase 1 caps a run's journal and has no checkpoints, units of work are already short. Phase 2 checkpoints only at suspension points once closures capture only free variables.
- O6 resolved (Rui): admission slots per workspace and channel, a separate model call limit, suspended runs hold no slot, a child borrows its parent's slot, Delegate depth capped at 4, ingestion pauses at the source.
- O7 resolved (Sam): placeholders become random handles per secret version, injection only where a program names the secret, implicit Bearer injection becomes a logged, deprecated opt in.
- O8 resolved (Priya, Sam): members read their channel's history, binding grants powers not history, an admin or auditor outside the channel reads it through a recorded ChannelHistoryOpened with a reason.
- O9 resolved (Rui, Priya): a reminder belongs to its conversation and survives /new, erasure of the conversation cancels it.
- O10 ruled (Rui, Priya): an identical card is a no op. A changed card is an explicit TriggerReplaced with both definition CIDs, offered as one click when the same person submits it, a deliberate replace when someone else added it, rejected when the name is in workspace.eyg.

## Removed during the session
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