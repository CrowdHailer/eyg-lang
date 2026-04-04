--- migration:up

CREATE TABLE module_uploads (
  id          BIGSERIAL   PRIMARY KEY,
  ip          INET        NOT NULL,
  cid         TEXT        REFERENCES modules(cid),
  uploaded_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX ON module_uploads (ip, uploaded_at);

--- migration:down

DROP TABLE module_uploads;

--- migration:end