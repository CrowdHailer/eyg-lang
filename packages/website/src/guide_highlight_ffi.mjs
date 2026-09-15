import { readFile } from 'node:fs/promises';
import { createHighlighterCore } from 'shiki/core';
import { createOnigurumaEngine } from 'shiki/engine/oniguruma';
import githubDark from 'shiki/themes/github-dark.mjs';

const grammar = JSON.parse(await readFile('../vscode-eyg/syntaxes/eyg.tmLanguage.json', 'utf8'));

// Shared by all guide renders in this build process; never a browser entrypoint.
const highlighter = await createHighlighterCore({
  langs: [grammar],
  themes: [githubDark],
  engine: createOnigurumaEngine(import('shiki/wasm')),
});

export function highlight(source) {
  const { bg, fg, tokens } = highlighter.codeToTokens(source, {
    lang: 'eyg',
    theme: 'github-dark',
  });
  return [bg, fg, tokens.map(line => line.map(token => [token.content, token.color ?? fg]))];
}
