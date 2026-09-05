---
name: Managing signatories
description: Create, inspect, protect, and use signatories with the EYG CLI.
---

A signatory is an identity that signs EYG package releases. The hub uses the
signatory's principal to decide whether a release is authorised for a package
name, and the CLI uses a locally stored private key to create the signature.

## Concepts

Each locally configured signatory has:

- An **alias**, such as `personal` or `work`. The alias is a local name chosen
  for convenience and is not submitted as the signatory's identity.
- A **principal CID**, such as `baguqe...`. This is the signatory's identity on
  an EYG hub and is the value used when granting permission to publish a
  package.
- A **keypair**. The private key remains in the local signatory file and is used
  to sign releases. Do not share it.

Signatories can contain a history of keys on the hub. The current CLI stores
one local keypair for each signatory and does not yet provide key-management
commands.

## Create a signatory

Choose a descriptive local alias and run:

```sh
eyg signatory initial personal
```

Use an alias that is not already configured. The current CLI does not check
for an existing alias before writing `<alias>.json`, so reusing an alias can
replace the local credentials for the earlier signatory.

The command generates a keypair, submits the initial principal entry to the
configured hub, stores the principal CID and keypair locally, and prints the
alias and principal CID.

Creation requires the hub to be available. If submission fails, no local
signatory is saved. If submission succeeds but writing the local file fails,
the principal exists on the hub but its generated private key has not been
saved by the CLI.

### Select a hub

The CLI uses `https://eyg.run` by default. Set `EYG_ORIGIN` to create the
signatory on another hub:

```sh
EYG_ORIGIN=http://localhost:8001 eyg signatory initial personal
```

`EYG_ORIGIN` applies to all hub operations, including signatory creation,
sharing, fetching, and publishing. Use the same origin when publishing that
you used when registering and granting permissions to the signatory.

## List configured signatories

The CLI does not currently have a list command. Until `eyg signatory list` is
implemented, inspect the signatory directory without printing the private
key.

On Linux, with `jq` installed:

```sh
config_dir="${XDG_CONFIG_HOME:-$HOME/.config}"
for file in "$config_dir/eyg/signatories/"*.json; do
  [ -e "$file" ] || continue
  jq -r --arg alias "$(basename "$file" .json)" \
    '[$alias, .principal] | @tsv' "$file"
done
```

This command prints the local alias and principal CID only. Do not print or
copy the `keypair` field while inspecting a signatory file.

On macOS, run the same loop with its XDG-aware config directory:

```sh
config_dir="${XDG_CONFIG_HOME:-$HOME/Library/Application Support}"
```

On Windows, signatory files can be listed in PowerShell without displaying
their keypairs:

```powershell
Get-ChildItem "$env:APPDATA\eyg\signatories\*.json" | ForEach-Object {
  $signatory = Get-Content $_.FullName | ConvertFrom-Json
  "{0}`t{1}" -f $_.BaseName, $signatory.principal
}
```

## Local storage

Signatories are stored in the platform's configuration directory:

| Platform | Directory |
|---|---|
| Linux | `${XDG_CONFIG_HOME:-$HOME/.config}/eyg/signatories/` |
| macOS | `${XDG_CONFIG_HOME:-$HOME/Library/Application Support}/eyg/signatories/` |
| Windows | `%APPDATA%\eyg\signatories\` |

Each alias is stored as `<alias>.json`. The file contains the principal CID
and the private key encoded as PEM. New files are given owner-only `0600`
permissions. Keep those permissions restrictive and never commit signatory
files to source control, upload them, or include their contents in logs.

The principal history downloaded from the hub is cached separately. The cache
is not a credential backup because it does not contain the private key.

## Back up and restore

There are no backup or restore commands yet. To back up a signatory, copy its
JSON file to encrypted storage while preserving owner-only access. Treat the
backup like a password or signing key.

To restore it, place the file back in the signatory directory for the current
platform, retain its `<alias>.json` name, and set access so only your account
can read or write it. On Linux and macOS:

```sh
chmod 600 /path/to/restored/signatory.json
```

The hub stores public signatory history, not the private key. A private key
cannot be recovered from the principal CID or downloaded from the hub. If both
the local file and every backup are lost, the current CLI cannot sign another
release as that signatory.

Deleting a local file only removes that machine's credentials. It does not
delete the signatory, its history, package permissions, or published releases
from a hub. Do not delete the last copy of a signatory file unless the identity
is no longer needed.

## Publish with a signatory

Before a signatory can publish, the hub must grant its principal CID ownership
of the package name. Public package-name claiming is not currently available;
hub administrators grant ownership.

Publish a release with:

```sh
eyg publish package-name path/to/file.eyg
```

The current CLI chooses a signatory implicitly:

| Local signatories | Result |
|---|---|
| None | Publishing fails with `No signatories created.` |
| One | That signatory signs the release. |
| More than one | Publishing fails with `Multiple signatories created`. |

There is currently no flag to select among multiple signatories. Do not work
around this by repeatedly moving credential files; explicit selection is part
of the roadmap below.

## Roadmap

Signatory management should be possible without reading or moving credential
files directly. The complete proposed user-facing command set is:

| Command | Purpose | Status |
|---|---|---|
| `eyg signatory initial <name>` | Create and register a signatory, refusing to replace an existing alias. | Available; collision check required |
| `eyg signatory list` | List local aliases and principal CIDs without exposing keys. | Required |
| `eyg signatory show <name>` | Show safe local metadata and the configured hub status. | Required |
| `eyg publish --signatory <name> <package> <file>` | Explicitly choose the signer when publishing. | Required |
| `eyg signatory rename <name> <new-name>` | Change the local alias without changing the principal. | Required |
| `eyg signatory backup <name> <file>` | Create a protected, portable credential backup. | Required |
| `eyg signatory restore <file> [<name>]` | Restore a backup, optionally under a new local alias. | Required |
| `eyg signatory remove <name>` | Remove local credentials after warning about the last copy. | Required |
| `eyg signatory key add <name>` | Add and store a new signing key in the signatory history. | Required |
| `eyg signatory key list <name>` | List key identifiers and their status without private data. | Required |
| `eyg signatory key revoke <name> <key>` | Revoke a signing key while another authorised key remains. | Required |
| `eyg signatory key rotate <name>` | Add a replacement key and revoke the previous key safely. | Required |

Backup and restore commands must avoid writing private keys to standard output,
must create files with owner-only permissions, and should support encrypted
backups. Removal and key revocation must clearly distinguish local credential
changes from persistent hub history.
