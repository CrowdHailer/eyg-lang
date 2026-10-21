import { readFile } from 'node:fs/promises';
import { bundledLanguagesInfo, createHighlighter } from 'shiki';
import githubDark from 'shiki/themes/github-dark.mjs';

const grammar = JSON.parse(await readFile('../vscode-eyg/syntaxes/eyg.tmLanguage.json', 'utf8'));

// Shared by all guide renders in this build process; never a browser entrypoint.
const highlighter = await createHighlighter({
  langs: [...bundledLanguagesInfo.map(language => language.id), grammar],
  themes: [githubDark],
});

export function supportsLanguage(language) {
  return highlighter.getLoadedLanguages().includes(language);
}

export function highlight(source, language) {
  const { bg, fg, tokens } = highlighter.codeToTokens(source, {
    lang: language,
    theme: 'github-dark',
  });
  return [bg, fg, tokens.map(line => line.map(token => [token.content, token.color ?? fg]))];
}
