# EYG Identity and Publishing System

## Overview

EYG uses a cryptographic identity system to authenticate package publications. A **principal** is a persistent identity — an append-only chain of key membership events held on the hub. A **signatory** is a machine-local keypair that is currently authorised to act on behalf of a principal. One principal may have many signatories across different devices; one device holds exactly one signatory per principal it can act as.

Publishing a package requires a signatory to sign a release entry linking a package name, version sequence, and module CID. The hub verifies the signature against the principal's current authorised key set before accepting the entry.

---

## Filesystem Layout

Local state is split across two XDG directories reflecting the different nature of each kind of data.

**Configuration** — user-managed, persists intentionally:

```
~/.config/eyg/signatories/
  peter-saxton.json       ← private key, key_id, principal_cid, human name
```

**Cache** — hub-derived, reconstructible by pulling from the hub:

```
~/.cache/eyg/principals/
  <principal-cid>.json    ← cached ArchivedEntry history for that principal
```

The signatory file is named after the principal it represents, not after the key itself. The key is an implementation detail; the principal is the identity the user cares about. The cache is keyed by principal CID because it is shared state — the same principal history is relevant to any signatory of that principal, on any machine.

---

## CLI Commands

```
eyg signatory new <name>
```
Creates a new principal from scratch. Generates a keypair, submits the bootstrap entry to the hub, and writes the signatory file. The returned principal CID is stored in the signatory file and its history cached locally.

```
eyg signatory join <name> --principal <principal-cid>
```
Registers this machine as a candidate signatory for an existing principal. Generates a keypair locally but does not submit anything to the hub — the new `key_id` must be authorised by an existing signatory, typically on another device.

```
eyg signatory add-key <name> --key-id <key-id>
```
Adds a foreign key to the principal this signatory belongs to. Signs and submits an `AddKey` entry to the hub. This is the authorisation step that completes a `join` from another device.

```
eyg signatory status <name>
```
Fetches the latest principal history from the hub and displays the current set of authorised keys, indicating which one belongs to this machine. Useful for auditing access and confirming whether a lost device's key needs revoking.

History is otherwise managed automatically: any command that talks to the hub updates the local cache as a side effect. `signatory status` is a recovery and audit tool, not a required step in normal workflows.

---

## Name Choices

**Principal** — the persistent identity. Owns a package namespace, accumulates a publication history. Outlives any individual key or device.

**Signatory** — the machine-local credential. A keypair that currently speaks for a principal. The distinction matters operationally: when a device is lost, you revoke the signatory, not the principal. The principal and its publication history remain intact.

The signatory file is named after the principal rather than the key because the principal is what the user identifies with. A key is rotated and replaced; a principal persists.

---

## Alternative Terms in Similar Systems

The concepts here have close analogues in other systems, under different names.

| This system | PGP | SSH | Lampson et al. 1992 | Certificate PKI |
|---|---|---|---|---|
| Principal | Identity / UID | — | Compound principal | Subject |
| Signatory | Subkey | Authorised key | Delegate | End-entity certificate |
| `add-key` | Sign subkey | `authorized_keys` entry | Speaks-for certificate | Certificate issuance |
| Hub history | Keyserver / Web of Trust | — | Certificate chain | CRL / OCSP |

Lampson et al. (1992) treat a bare public key as a principal in its own right, making delegation explicit through speaks-for certificates. This system instead treats the principal as the chain of membership events, which is closer to a mutable group principal in their algebra — simpler, but stateful rather than purely certificate-driven.
