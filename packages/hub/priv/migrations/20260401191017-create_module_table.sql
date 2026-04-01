--- migration:up

CREATE TABLE modules (
  -- TEXT is as performant as VARCHAR without an arbitrary length constraint
  cid        TEXT        PRIMARY KEY,
  source     JSONB       NOT NULL,
  inserted_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

--- migration:down

DROP TABLE modules;

--- migration:end