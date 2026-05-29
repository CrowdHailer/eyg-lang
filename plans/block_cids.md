# Snippet Sharing Implementation Plan

## Overview

Snippets are shared by content identifier (CID) using the multiformats standard. The CID is derived from the canonical form of the source code, making storage naturally idempotent — uploading the same snippet twice is a no-op.

## Schema

```sql
CREATE TABLE snippets (
  cid        TEXT        PRIMARY KEY,
  source     JSONB       NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE snippet_uploads (
  id          BIGSERIAL   PRIMARY KEY,
  ip          TEXT        NOT NULL,
  cid         TEXT        REFERENCES snippets(cid),
  uploaded_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX ON snippet_uploads (ip, uploaded_at);

CREATE TABLE ip_block_history (
  id         BIGSERIAL   PRIMARY KEY,
  ip         TEXT        NOT NULL,
  is_blocked BOOLEAN     NOT NULL,
  reason     TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX ON ip_block_history (ip, created_at);

CREATE VIEW blocked_ips AS
SELECT DISTINCT ON (ip) ip, is_blocked, reason, created_at
FROM ip_block_history
WHERE is_blocked = true
ORDER BY ip, created_at DESC;
```

## API

| Method | Route | Description |
|--------|-------|-------------|
| `POST` | `/snippets` | Upload a snippet, returns its CID |
| `GET`  | `/snippets/:cid` | Fetch a snippet by CID |

## Request Lifecycle

### Upload (`POST /snippets`)

1. Reject bodies exceeding the size limit at the HTTP layer
2. Check `blocked_ips` — return `403` if matched
3. Count rows in `snippet_uploads` for this IP in the last 10 minutes — return `429` if over limit
4. Validate the CID format (multibase prefix, multicodec, multihash)
5. Recompute the CID server-side and reject if it does not match the claimed CID
6. `INSERT INTO snippets ... ON CONFLICT DO NOTHING`
7. Insert a row into `snippet_uploads` regardless of whether the snippet was new
8. Return the CID

### Fetch (`GET /snippets/:cid`)

1. Check `blocked_cids` (view) — return `410 Gone` if matched
2. Look up snippet by CID — return `404` if not found
3. Return source JSON with `Cache-Control: immutable, max-age=31536000`

## Rate Limiting

Limits are enforced per IP using `snippet_uploads`:

```sql
SELECT COUNT(*) FROM snippet_uploads
WHERE ip = $1
AND uploaded_at > now() - interval '10 minutes';
```

A separate (stricter) limit applies to writes vs reads. Old rows should be purged periodically to keep the table lean.

## IP Blocking

To block an IP, insert a row with `is_blocked = true`. To unblock, insert with `is_blocked = false`. The view always reflects the latest state. All history is retained for audit purposes.

---

## Next Step: CID Block History

The next feature mirrors the IP blocking approach — a history table with a view for the current blocked status of a CID.

### Tests Required

**Blocking**
- Inserting a row with `is_blocked = true` causes the CID to appear in the `blocked_cids` view
- Inserting a subsequent row with `is_blocked = false` removes the CID from the view
- Re-blocking a previously unblocked CID causes it to reappear in the view
- The history table retains all rows across block/unblock cycles

**View correctness**
- The view returns only the most recent status per CID
- A CID with multiple block history rows reflects only the latest `is_blocked` value
- A CID that has never been blocked does not appear in the view
- A CID blocked, unblocked, and reblocked appears exactly once in the view

**Fetch behaviour**
- `GET /snippets/:cid` returns `410 Gone` for a blocked CID
- `GET /snippets/:cid` returns `200` after a CID is unblocked
- Blocking a CID does not delete the row from `snippets`

**Foreign key**
- Inserting a `cid_block_history` row for a non-existent CID is rejected
- Inserting for a valid CID succeeds

**Reason field**
- A block entry with a reason persists the reason correctly
- A block entry with no reason is accepted (reason is nullable)