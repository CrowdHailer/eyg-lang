--- migration:up

-- A chat is a conversation with an llm about a box.
CREATE TABLE chats (
  id TEXT PRIMARY KEY DEFAULT gen_random_uuid()::TEXT,
  box TEXT NOT NULL REFERENCES boxes(id),
  llm TEXT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX chats_box_idx ON chats (box);

-- What happened in a chat, in order. Entries are only ever appended, by the chat and by people sending messages to it.
CREATE TABLE chat_journal (
  id BIGSERIAL PRIMARY KEY,
  chat TEXT NOT NULL REFERENCES chats(id),
  entry JSONB NOT NULL,
  recorded_at TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp()
);

CREATE INDEX chat_journal_chat_idx ON chat_journal (chat, id);

-- The code of each tool call a chat's llm makes runs in a shell of its own.
-- A tool call sent through the API has a call and no chat.
ALTER TABLE shells ADD COLUMN chat TEXT REFERENCES chats(id);
ALTER TABLE shells ADD COLUMN call TEXT;
-- Each tool call of a chat has one shell, so a call is never run twice.
ALTER TABLE shells ADD CONSTRAINT shells_call_is_unique UNIQUE (chat, call);

--- migration:down

ALTER TABLE shells DROP CONSTRAINT shells_call_is_unique;
ALTER TABLE shells DROP COLUMN call;
ALTER TABLE shells DROP COLUMN chat;
DROP TABLE chat_journal;
DROP TABLE chats;

--- migration:end
