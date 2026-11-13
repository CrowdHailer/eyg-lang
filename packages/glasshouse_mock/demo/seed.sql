-- Newsletter signups for the demo agent.
CREATE TABLE signups (id integer PRIMARY KEY, email text NOT NULL, source text, created timestamptz);
INSERT INTO signups (id, email, source, created) VALUES
  (1, 'ada@example.com', 'blog', '2026-10-05 09:12:00+00'),
  (2, 'grace@example.com', 'talk', '2026-10-06 14:30:00+00'),
  (3, 'alan@example.com', 'blog', '2026-10-07 08:45:00+00'),
  (4, 'edsger@example.com', 'social', '2026-10-08 19:02:00+00'),
  (5, 'barbara@example.com', 'blog', '2026-10-09 11:20:00+00'),
  (6, 'ken@example.com', NULL, '2026-10-10 16:05:00+00'),
  (7, 'margaret@example.com', 'talk', '2026-10-11 10:40:00+00');
