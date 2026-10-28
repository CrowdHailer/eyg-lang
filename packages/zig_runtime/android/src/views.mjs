// React and the Expo registry are injected so the descriptor protocol can be
// exercised without loading Android modules in a Node test process.
/**
 * @param {any} spec
 * @param {any} host
 * @param {(...args: any[]) => any} createElement
 * @param {{rootStyle?: unknown, emit?: (topic: string, args: unknown[]) => void, current?: () => boolean, maxDepth?: number}} options
 */
export function renderView(spec, host, createElement, options = {}) {
  const { rootStyle, emit = () => {}, current = () => true, maxDepth = 64 } = options;
  if (!Number.isSafeInteger(maxDepth) || maxDepth < 1 || maxDepth > 64) throw new Error('Invalid native view depth limit');
  const seen = new Set();

  function render(value, depth) {
    if (!current()) throw new Error('Closed EYG run');
    if (value == null || typeof value === 'string' || typeof value === 'boolean') return value;
    if (typeof value === 'number' && Number.isFinite(value)) return value;
    if (typeof value !== 'object') throw new Error('Native view children must be descriptors or text');
    if (depth >= maxDepth) throw new Error('Native view tree exceeds depth limit');
    if (seen.has(value)) throw new Error('Cyclic native view tree');
    seen.add(value);
    try {
      if (Array.isArray(value)) return value.map(child => render(child, depth + 1));
      if (typeof value.module !== 'string' || !Object.hasOwn(host.modules, value.module)) throw new Error('Unknown native view module');
      const component = host.path(host.modules[value.module], value.component).value;
      const callable = typeof component === 'function' || typeof component === 'string';
      if (!callable && !(component && typeof component === 'object' && typeof component.$$typeof === 'symbol')) throw new Error('Invalid native view component');
      if (value.props != null && (typeof value.props !== 'object' || Array.isArray(value.props))) throw new Error('Native view props must be a record');
      const props = host.decode(value.props ?? {});
      if (depth === 0 && rootStyle !== undefined) props.style = [rootStyle, props.style];
      if (value.ref != null && value.ref !== false) {
        const topic = typeof value.ref === 'string' ? value.ref : value.ref === true && typeof value.id === 'string' && value.id ? `view:${value.id}:ready` : null;
        if (!topic) throw new Error('Native view ref needs an id or topic');
        props.ref = instance => {
          if (instance != null && current()) emit(topic, [host.encode(instance)]);
        };
      }
      const children = Object.hasOwn(value, 'children') ? (Array.isArray(value.children) ? value.children : [value.children]) : [];
      return createElement(component, props, ...children.map(child => render(child, depth + 1)));
    } finally {
      seen.delete(value);
    }
  }

  return render(spec, 0);
}
