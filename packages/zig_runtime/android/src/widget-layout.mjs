// Expo's Babel preset serializes this self-contained function for its separate
// widget JS runtime. It cannot capture the foreground interpreter or callbacks.
export function eygLayout(props) {
  'widget';
  function render(node, depth = 0) {
    if (node == null || typeof node === 'string' || typeof node === 'number') return node;
    if (depth >= 32 || typeof node !== 'object' || Array.isArray(node)) throw new Error('Invalid EYG widget tree');
    const allowed = ['Text', 'Column', 'Row', 'Box', 'Image', 'Icon', 'Button', 'Spacer', 'Divider', 'Checkbox', 'Switch', 'Card', 'LinearProgressIndicator', 'CircularProgressIndicator', 'LinearWavyProgressIndicator', 'CircularWavyProgressIndicator'];
    if (!allowed.includes(node.component)) throw new Error('Unsupported EYG widget component');
    const component = globalThis[node.component];
    if (typeof component !== 'function' && typeof component !== 'string') throw new Error('Unavailable EYG widget component');
    if (node.props != null && (typeof node.props !== 'object' || Array.isArray(node.props))) throw new Error('Invalid EYG widget props');
    const children = node.children == null ? [] : Array.isArray(node.children) ? node.children : [node.children];
    return globalThis.React.createElement(component, node.props ?? {}, ...children.map(child => render(child, depth + 1)));
  }
  if (props.sections) {
    const sections = { collapsed: render(props.sections.collapsed) };
    if (props.sections.expanded != null) sections.expanded = render(props.sections.expanded);
    if (props.sections.headsUp != null) sections.headsUp = render(props.sections.headsUp);
    return sections;
  }
  return render(props.tree ?? { component: 'Text', children: props.text ?? 'EYG' });
}
