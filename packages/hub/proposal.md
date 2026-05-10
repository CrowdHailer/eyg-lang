# Package Ownership Permissions

## Problem

The hub allows any authenticated signatory to publish any package name. This means a bad actor who controls a valid signatory can publish a package with the same name as one already published by another entity. Without ownership tracking there is no way to enforce that the same entity controls a package across releases.

## Solution

### New table: `package_owners`

A append-only ledger that records when a signatory entity claimed ownership of a package name.

```sql
CREATE TABLE package_owners (
  id BIGSERIAL PRIMARY KEY,
  package TEXT NOT NULL,
  entity_id TEXT NOT NULL,
  recorded_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
```

Rows are protected from mutation by PostgreSQL rules, consistent with the approach used for `package_entries` and `signatory_entries`:

```sql
CREATE RULE protect_package_owners_updates AS ON UPDATE TO package_owners DO INSTEAD NOTHING;
CREATE RULE protect_package_owners_deletes AS ON DELETE TO package_owners DO INSTEAD NOTHING;
```

This means ownership history is preserved even if the current owner later changes (e.g. through a future transfer mechanism).

### New view: `current_package_owners`

Shows the most recent ownership record per package:

```sql
CREATE VIEW current_package_owners AS
SELECT DISTINCT ON (package)
  package,
  entity_id,
  recorded_at
FROM package_owners
ORDER BY package, id DESC;
```

Using `DISTINCT ON … ORDER BY id DESC` means the view reflects the latest entry, making it straightforward to add ownership transfers later by inserting a new row.

### Ownership check in the publish flow

Before a release is recorded, the hub checks the `current_package_owners` view:

1. **No existing owner** — the publishing signatory entity is recorded as the owner, and the release proceeds.
2. **Existing owner matches the submitter** — the release proceeds.
3. **Existing owner is a different entity** — the request is rejected with `does_not_have_permission` (HTTP 403).

The check lives in `packages/controller.gleam` as `check_package_ownership/3`, called after the existing signatory authentication and permission checks so that ownership is only evaluated for already-trusted signatories.

The `entity_id` used for ownership is `entry.signatory` — the CID of the signatory entity chain — which is stable across key rotations within a signatory.

## Tests

New tests cover:

- **Data layer** (`packages/data_test.gleam`):
  - `record_and_fetch_package_owner_test` — writing and reading an ownership record via `record_owner` and `get_current_owner`.
  - `get_current_owner_returns_empty_for_unknown_package_test` — no owner row means no result.
  - `current_owner_reflects_most_recent_record_test` — the view returns the latest record when multiple exist.
  - `ownership_records_are_never_deleted_test` — verifies the DELETE rule prevents removal.

- **Controller layer** (`packages/controller_test.gleam`):
  - `reject_publish_by_different_entity_test` — a second signatory entity cannot publish to a package already claimed by the first.
  - `allow_owner_to_publish_after_another_package_test` — the original owner can continue publishing new versions.

All 39 tests pass.

## Next Steps

- **Atomicity**: The ownership claim and the release insert are separate database operations. A concurrent first publish could result in both entities believing they claimed ownership. Wrapping the full `submit` handler in an explicit `pog.transaction` call, or using `INSERT INTO package_owners … ON CONFLICT DO NOTHING` with a unique index on `package`, would close this race.

- **Unique index on package**: Adding `CREATE UNIQUE INDEX package_owners_unique_current_owner ON package_owners (package)` (or a partial index on the latest row per package) would enforce ownership constraints at the database level rather than relying solely on application logic. This would also make the current `current_package_owners` view query cheaper for large tables.

- **Ownership transfers**: The append-only design supports future ownership transfers — insert a new row with the new entity, and the view reflects the change automatically. A transfer endpoint with appropriate authorization (e.g. the current owner signs a transfer entry) would need to be added.

- **Package name validation**: The system currently trusts any string as a valid package name. Enforcing a naming policy (e.g. lowercase alphanumeric with hyphens, maximum length) at the database or application layer would prevent squatting on unusual names and improve ergonomics.

- **Ownership visibility**: No public endpoint exposes ownership data. Adding a `GET /packages/:name/owner` endpoint (or including ownership information in the package listing) would allow clients and tooling to surface this information.

- **Removing the `echo permission` debug statement**: The controller currently prints the permission to stdout on every publish request. This should be removed before production use.
