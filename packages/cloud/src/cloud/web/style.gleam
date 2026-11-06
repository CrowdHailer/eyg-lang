//// Styles for the terminal and session list.
//// Lustre copies document styles into each component's shadow root,
//// so these apply inside the live views too.

pub const css =
  "
:root {
  --term-bg: #16181d;
  --term-fg: #d7dae0;
  --term-muted: #8b919c;
  --term-accent: #7ec699;
  --ansi-0: #3b4048;  --ansi-8: #5c6370;
  --ansi-1: #ef6b73;  --ansi-9: #ff8b92;
  --ansi-2: #7ec699;  --ansi-10: #a5e0b4;
  --ansi-3: #e5c07b;  --ansi-11: #f0d399;
  --ansi-4: #61afef;  --ansi-12: #8cc5f5;
  --ansi-5: #c678dd;  --ansi-13: #d99ae8;
  --ansi-6: #56b6c2;  --ansi-14: #7fcbd4;
  --ansi-7: #d7dae0;  --ansi-15: #ffffff;
  --term-font: ui-monospace, SFMono-Regular, Menlo, Consolas, 'Liberation Mono', monospace;
}
html, body { height: 100%; margin: 0; }
[data-howdy-sidebar-layout] { height: 100vh; }
[data-howdy-sidebar-layout] > main { min-width: 0; height: 100vh; height: 100dvh; display: flex; flex-direction: column; }
.mobile-bar { display: none; }
@media (max-width: 48rem) {
  .mobile-bar {
    display: flex; align-items: center; gap: 12px; padding: 8px 12px;
    background: var(--term-bg); color: var(--term-fg); border-bottom: 1px solid #262a31; font-weight: 600;
  }
  .mobile-bar button {
    font-size: 18px; line-height: 1; padding: 6px 10px; color: inherit;
    background: #1f2329; border: 1px solid #2f343c; border-radius: 6px;
  }
}
[data-howdy-sidebar-layout] > main > lustre-server-component { flex: 1; min-width: 0; display: flex; }
.brand { font-weight: 600; text-decoration: none; color: inherit; }
.new-session {
  display: block; margin: 0 0 12px; padding: 8px 10px; border-radius: 6px;
  text-decoration: none; color: inherit; border: 1px dashed currentColor; opacity: .8;
}
.new-session:hover { opacity: 1; }
.session-item { display: flex; flex-direction: column; min-width: 0; }
.session-title { font-family: var(--term-font); font-size: 13px; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
.session-meta { font-size: 11px; opacity: .65; }

.terminal {
  flex: 1; min-width: 0; display: flex; flex-direction: column;
  background: var(--term-bg); color: var(--term-fg); position: relative;
  font-family: var(--term-font);
}
.terminal-bar {
  display: flex; gap: 16px; justify-content: space-between; align-items: center;
  padding: 8px 16px; border-bottom: 1px solid #262a31; font-size: 12px; color: var(--term-muted);
}
.terminal-title { color: var(--term-fg); overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
.terminal-root { margin-left: auto; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
.terminal-root code { font-family: var(--term-font); }
.terminal a { color: var(--ansi-4); }
.blink { animation: blink 1.1s steps(1) infinite; }
@keyframes blink { 50% { background-color: transparent; color: inherit; } }
.terminal:not(:focus-within) .blink {
  animation: none; background-color: transparent !important; color: inherit !important;
  outline: 1px solid var(--term-muted); outline-offset: -1px;
}
.terminal-scroll:focus { outline: none; }
.terminal-scroll:focus-visible { box-shadow: inset 0 0 0 1px #3b4048; }
.terminal-scroll {
  flex: 1; min-height: 0; overflow-y: auto; display: flex; flex-direction: column-reverse;
  cursor: text;
}
.terminal-screen {
  margin: 0; padding: 12px 16px 24px; font-family: var(--term-font); font-size: 14px; line-height: 1.5;
  white-space: pre-wrap; overflow-wrap: anywhere; color: var(--term-fg);
}
.term-line { min-height: 1.5em; }
.step { position: relative; }
.step + .step { margin-top: 4px; }
.step.inherited { opacity: .6; }
.divider { margin: 8px 0; border-top: 1px dashed #3b4048; padding-top: 4px; color: var(--term-muted); }
.fork { position: absolute; right: 0; top: 0; margin: 0; opacity: 0; transition: opacity .1s; user-select: none; }
.step:hover .fork, .fork:focus-within { opacity: 1; }
@media (hover: none) { .fork { opacity: .8; position: static; float: right; margin-left: 8px; } }
.fork button {
  font: 12px var(--term-font); color: var(--term-accent); background: #1f2329;
  border: 1px solid #2f343c; border-radius: 4px; padding: 1px 8px; cursor: pointer;
}
.fork button:hover { border-color: var(--term-accent); }
"
