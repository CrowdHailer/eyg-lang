import { Result$Ok, Result$Error, toList } from '../../gleam.mjs';
export const document = () => globalThis.document;
export const root = () => globalThis.document.documentElement;
export const body = () => globalThis.document.body;
export const active = () => globalThis.document.activeElement ? Result$Ok(globalThis.document.activeElement) : Result$Error(undefined);
export function query(node, selector) {
  try { return Result$Ok(toList(node.querySelectorAll(selector))); }
  catch (error) { return Result$Error(String(error)); }
}
export const getById = id => globalThis.document.getElementById(id) ? Result$Ok(globalThis.document.getElementById(id)) : Result$Error(undefined);
export const create = tag => globalThis.document.createElement(tag);
export const clone = node => node.cloneNode(true);
export const append = (node, child) => { node.append(child); };
export const remove = node => { node.remove(); };
export const replace = (node, replacement) => { node.replaceWith(replacement); };
export const contains = (node, child) => node.contains(child);
export const labels = node => toList(node.labels ?? []);
export const text = (node, property) => String(node[property] ?? '');
export const value = node => 'value' in node ? Result$Ok(String(node.value)) : Result$Error(undefined);
export const setText = (node, property, value) => { node[property] = value; };
export const flag = (node, property) => Boolean(node[property]);
export const number = (node, property) => Number(node[property] ?? 0);
export const setNumber = (node, property, value) => { node[property] = value; };
export const isType = (node, constructor) => typeof globalThis[constructor] === 'function' && node instanceof globalThis[constructor];
export const attribute = (node, name) => node.getAttribute(name) === null ? Result$Error(undefined) : Result$Ok(node.getAttribute(name));
export const setAttribute = (node, name, value) => { node.setAttribute(name, value); };
export const removeAttribute = (node, name) => { node.removeAttribute(name); };
export const style = (node, name, value) => { node.style.setProperty(name, value); };
export const computedStyle = (node, name) => getComputedStyle(node).getPropertyValue(name);
export const checkVisibility = node => node.checkVisibility({checkOpacity:false, checkVisibilityCSS:true});
export const rect = node => { const r = node.getBoundingClientRect(); return [r.left,r.top,r.width,r.height]; };
export const focus = node => { node.focus({preventScroll:true}); };
export const click = node => { node.click(); };
export const scroll = (node, block) => { node.scrollIntoView({block,inline:'nearest'}); };
export const event = (node, name) => node.dispatchEvent(new Event(name,{bubbles:true}));
export const keyboard = (node, name, key) => node.dispatchEvent(new KeyboardEvent(name,{key,bubbles:true,cancelable:true,composed:true}));
export const pointer = (node, constructor, name, x, y) => node.dispatchEvent(new globalThis[constructor](name,{bubbles:true,cancelable:true,composed:true,clientX:x,clientY:y,button:0}));
export const setInheritedValue = (node, constructor, value) => { Object.getOwnPropertyDescriptor(globalThis[constructor].prototype,'value').set.call(node,value); };
export const form = node => node.form ? Result$Ok(node.form) : Result$Error(undefined);
export const submit = node => { node.requestSubmit(); };
export const serialize = node => new XMLSerializer().serializeToString(node);
export const escapeCss = text => CSS.escape(text);
export const encodeUri = text => encodeURIComponent(text);
export const windowNumber = property => Number(globalThis[property] ?? 0);
export const now = () => Date.now();
export const sleep = milliseconds => new Promise(resolve => setTimeout(() => resolve(undefined), milliseconds));
export const frame = () => new Promise(resolve => requestAnimationFrame(() => resolve(undefined)));
export const fontsReady = () => globalThis.document.fonts.ready.then(() => undefined);
export const onMessage = handle => { addEventListener('message',handle); };
export const fromParent = message => message.source === parent;
export const messageData = message => message.data;
export const postToHost = message => { parent.parent.postMessage(JSON.parse(message),'*'); };
export const postToFrame = (node, message) => { node.contentWindow.postMessage(message,'*'); };
export const listen = (node,name,handler) => { node.addEventListener(name,handler); };
export const key = event => event.key;
export const target = event => event.target;
export const setFlag = (node,property,value) => { node[property]=value; };
export function tryText(node, property) {
  try { return Result$Ok(String(node[property] ?? '')); }
  catch(error) { return Result$Error(String(error)); }
}
export function readStorage(storage, key) {
  try { return Result$Ok(globalThis[storage].getItem(key) ?? ''); }
  catch(error) { return Result$Error(String(error)); }
}
export function openDatabase(name) {
  try { globalThis.indexedDB.open(name); return Result$Ok(undefined); }
  catch(error) { return Result$Error(String(error)); }
}
export function ancestorDocument(window) {
  try { return Result$Ok(globalThis[window].document); }
  catch(error) { return Result$Error(String(error)); }
}
