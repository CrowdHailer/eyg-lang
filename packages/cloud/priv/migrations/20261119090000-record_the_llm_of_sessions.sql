--- migration:up

-- The llm a session chats with, a session without one is a shell.
-- It is the first event of the session, it is kept here so sessions can be listed without reading their history.
ALTER TABLE sessions ADD COLUMN llm TEXT;

WITH RECURSIVE path AS (
  SELECT s.id AS session, t.parent, t.payload
  FROM sessions s JOIN thread_events t ON t.key = s.head
  UNION ALL
  SELECT path.session, t.parent, t.payload
  FROM thread_events t JOIN path ON t.key = path.parent
)
UPDATE sessions SET llm = path.payload::jsonb ->> 'llm'
FROM path
WHERE path.session = sessions.id
  AND path.parent IS NULL
  AND path.payload::jsonb ->> 'type' = 'configured';

--- migration:down

ALTER TABLE sessions DROP COLUMN llm;

--- migration:end
