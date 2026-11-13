import fs from 'node:fs';
import path from 'node:path';

export const infrastructure = new Set(['react', 'expo-modules-core', 'expo-build-properties', 'eyg-runtime']);
export const uiSubpaths = [
  '@expo/ui/jetpack-compose', '@expo/ui/jetpack-compose/modifiers',
  '@expo/ui/community/datetime-picker', '@expo/ui/community/bottom-sheet',
  '@expo/ui/community/segmented-control', '@expo/ui/community/picker',
  '@expo/ui/community/slider', '@expo/ui/community/masked-view',
  '@expo/ui/community/menu', '@expo/ui/community/pager-view',
];
export function registryEntries(root) {
  const manifest = JSON.parse(fs.readFileSync(path.join(root, 'package.json'), 'utf8'));
  return [...Object.keys(manifest.dependencies).filter(name => !infrastructure.has(name)), ...uiSubpaths].sort();
}
