--- migration:up

CREATE TABLE artifacts (
  id           UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  name         TEXT        NOT NULL,
  ip           INET        NOT NULL,
  -- SHA-256 of the secret given to whoever shared the artifact.
  secret_hash  BYTEA       NOT NULL,
  -- A newer version, shared with this artifact's secret.
  next_id      UUID        REFERENCES artifacts(id),
  inserted_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  -- Withdrawn artifacts are no longer served, as if they never existed.
  withdrawn_at TIMESTAMPTZ
);

CREATE INDEX ON artifacts (ip, inserted_at);

CREATE TABLE artifact_files (
  artifact_id UUID  NOT NULL REFERENCES artifacts(id),
  path        TEXT  NOT NULL,
  media_type  TEXT  NOT NULL,
  content     BYTEA NOT NULL,
  PRIMARY KEY (artifact_id, path)
);

--- migration:down

DROP TABLE artifact_files;
DROP TABLE artifacts;

--- migration:end
