import * as css from 'css-tree';

// No untrusted markup is ever parsed into the live application document.
// A template is inert, including images/iframes and custom elements.
const cache = new WeakMap();
const policy = "default-src 'none'; script-src 'unsafe-inline' data:; style-src 'unsafe-inline' data:; img-src data:; font-src data:; media-src data:; connect-src 'none'; frame-src 'none'; worker-src 'none'; object-src 'none'; base-uri 'none'; form-action 'none'";
const escape = text => text.replaceAll('&', '&amp;').replaceAll('"', '&quot;').replaceAll('<', '&lt;').replaceAll('>', '&gt;');

export function wrapper(html) {
  return `<!doctype html><html><head><meta charset="utf-8"><meta http-equiv="Content-Security-Policy" content="${policy}"><meta name="referrer" content="no-referrer"><style>html,body{margin:0;width:100%;height:100%;overflow:hidden}iframe{border:0;width:100%;height:100%;display:block}</style></head><body><iframe title="Artifact content" sandbox="allow-scripts" referrerpolicy="no-referrer" srcdoc="${escape(html)}"></iframe></body></html>`;
}

export function prepare(bundle, encode) {
  if (cache.has(bundle)) return cache.get(bundle);
  let result;
  try {
    result = wrapper(packageFiles(JSON.parse(encode(bundle))));
  } catch (error) {
    result = wrapper(`<h2>Unable to prepare artifact</h2><pre>${escape(error.message)}</pre>`);
  }
  cache.set(bundle, result);
  return result;
}

export function packageFiles(files) {
  const byPath = new Map(files.map(file => [file.path, file]));
  const decoder = new TextDecoder('utf-8', { fatal: true });
  const text = file => decoder.decode(Uint8Array.from(atob(file.content), c => c.charCodeAt(0)));
  const textURL = (type, value) => `data:${type};charset=utf-8,${encodeURIComponent(value)}`;
  const fileURL = file => {
    if (!/^[a-zA-Z0-9!#$&^_.+-]+\/[a-zA-Z0-9!#$&^_.+-]+$/.test(file.media_type)) {
      throw new Error(`Invalid media type for ${file.path}`);
    }
    return `data:${file.media_type};base64,${file.content}`;
  };
  function resolve(reference, from) {
    const url = new URL(reference, `https://bundle.invalid/${from}`);
    if (url.origin !== 'https://bundle.invalid') throw new Error(`External resource must be bundled: ${reference}`);
    const path = decodeURIComponent(url.pathname.slice(1));
    const file = byPath.get(path);
    if (!file) throw new Error(`Missing bundle file: ${path}`);
    return { file, hash: url.hash };
  }
  function asset(reference, from) {
    if (reference.startsWith('data:') || reference.startsWith('#')) return reference;
    const { file, hash } = resolve(reference, from);
    return fileURL(file) + hash;
  }
  function stylesheet(source, from, ancestors = [], context = 'stylesheet') {
    if (ancestors.includes(from)) throw new Error(`Circular CSS import: ${from}`);
    const ast = css.parse(source, { context, parseCustomProperty: true });
    css.walk(ast, {
      enter(node) {
        if (node.type === 'Atrule' && node.name.toLowerCase() === 'import') {
          const first = node.prelude?.children?.first;
          if (!first || !['String', 'Url'].includes(first.type)) throw new Error('Unsupported CSS import');
          const { file } = resolve(first.value, from);
          first.value = textURL('text/css', stylesheet(text(file), file.path, [...ancestors, from]));
        } else if (node.type === 'Url') {
          node.value = asset(node.value, from);
        }
      },
    });
    return css.generate(ast);
  }
  const entry = byPath.get('index.html');
  if (!entry) throw new Error('Missing index.html');
  const template = document.createElement('template');
  template.innerHTML = text(entry);
  for (const element of template.content.querySelectorAll('*')) {
    const tag = element.localName;
    if (tag === 'base') { element.remove(); continue; }
    if (tag === 'link') {
      if (element.rel.toLowerCase() !== 'stylesheet') { element.remove(); continue; }
      const { file } = resolve(element.getAttribute('href'), 'index.html');
      element.setAttribute('href', textURL('text/css', stylesheet(text(file), file.path)));
    }
    if (tag === 'style') element.textContent = stylesheet(element.textContent, 'index.html');
    if (element.hasAttribute('style')) {
      element.setAttribute('style', stylesheet(element.getAttribute('style'), 'index.html', [], 'declarationList'));
    }
    if (element.hasAttribute('srcset')) throw new Error('Use a bundled src instead of srcset');
    if (['img', 'script', 'audio', 'video', 'source', 'track', 'input'].includes(tag) && element.hasAttribute('src')) {
      element.setAttribute('src', asset(element.getAttribute('src'), 'index.html'));
      element.removeAttribute('integrity');
      element.removeAttribute('crossorigin');
    }
    if (element.hasAttribute('poster')) element.setAttribute('poster', asset(element.getAttribute('poster'), 'index.html'));
    if (tag === 'image' || tag === 'use') {
      for (const attr of ['href', 'xlink:href']) {
        if (element.hasAttribute(attr)) element.setAttribute(attr, asset(element.getAttribute(attr), 'index.html'));
      }
    }
  }
  return `<!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"></head><body>${template.innerHTML}</body></html>`;
}
