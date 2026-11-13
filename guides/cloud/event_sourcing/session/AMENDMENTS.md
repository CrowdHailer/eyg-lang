# Round 5: confirm the amendments

Dana agreed in round 4. Avery, Rui, Sam and Priya each raised one blocking objection. The facilitator accepted all four
(Priya's as a compromise) and four non-blocking objections. These are the only changes to STAGE3.md.

## Blocking objections, amended rulings

A1 (Rui, and Dana non-blocking). `secrets.SecretLeakRedacted` / RedactPayload: external effect results (Fetch, model completions) and inbound
messages are scanned for known secret values, which are replaced with the secret's opaque handle **before any block is put or inline payload
formed, and before the program resumes**. The program, the journal and every block see the same redacted value, so replay is exact
and no secret bytes are ever stored or hashed.

A2 (Sam). H1/H13 amended: **every digest in an event or envelope that is not a content CID** (input digests, rewrite digests, fingerprints,
subject digests) **is a keyed HMAC**, with the subject key when the payload carries personal data and the workspace key otherwise.
Shredding the key makes the digests meaningless. Content CIDs of encrypted blocks are unaffected.

A3 (Avery). O3 amended, four eyes also covers acts that **destroy or reinterpret evidence**: RetentionPolicySet that shortens a period,
LegalHoldReleased, SubjectKeyShredded (except a subject's own self service erasure), EventUpcasterRegistered, CheckpointKeyRotated,
TamperIncidentResolved, and AuditTrailExported when it includes payloads with personal data.

A4 (Priya, ruled as a compromise with Sam's and Avery's O3). **The shells catalogue in cloud.eyg is pre-approved**: changing it is a
CloudSourceChanged, and adding or widening a catalogue shell already needs a second person. So an admin who invites someone with, or assigns,
a catalogue shell other than `admin` approves it by issuing the command: PersonInvited or PersonShellAssigned with no PrivilegeChangeProposed.
Four eyes still applies to AdminGranted, shells outside the catalogue, ChannelShellChanged that widens, ArtifactVisibilityChanged to anyone
with the link, UnauthenticatedConnectionCreated, the evidence acts in A3, and anything an agent, trigger or schedule proposes.
A cloud with one admin may still self approve after 24 hours, flagged in every audit export.

## Non-blocking objections accepted

N1 (Avery, Sam, Priya, Dana). `configuration.CloudSourceChanged` gets the command SetCloudSource {source_cid, expected_previous_cid, reason, restores?}
issued by an admin person, and the aggregate CloudConfiguration on stream `configuration/cloud`, with the same compare and set as workspaces.
`access.PrivilegeChangeExpired` is a timer policy of the PrivilegeChange aggregate, fired by the durable wake up queue; the proposer is told where they asked.

N2 (Rui). H7 refined: **each stream is hash chained** (every event commits to the previous event of its own stream), the global position is
assigned at commit, and AuditLogCheckpointSigned signs a **Merkle root over all stream heads** at a global position. Tamper evidence is the same
and appends to different streams never contend on one chain head.

N3 (Sam, Avery reservation). Every `runs.*` event envelope names the **machine id and lease epoch** that appended it, appends with a stale epoch are
refused. MachineJoined carries the machine's public key and the operator credential that admitted it, and MachineJoined and MachineDrained are
evidence. Lease acquisitions and releases stay coordination with a short retention class.

N4 (Sam). SecretSet records name, version and keyed fingerprint only, the opaque handle exists only in the vault.

## Reservations recorded, not board changes

Restores (FileSystemRestored, FileRestored, DatabaseRestored) are forward only: a new root or sequence equal to an old state. The Activity view
uses plain words (edited, deleted, posted twice?, paused). Today's public artifact links need a migration to visibility. Constant time comparison
for webhook tokens. Erasure order is erasure dataclip, then a new snapshot, then SubjectKeyShredded. Exports are encrypted to their recipient.
