import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import { registryEntries } from './registry-entries.mjs';
import { bundleExclusions } from './bundle-exclusions.mjs';
const root = path.resolve(import.meta.dirname, '..');
const read = relative => JSON.parse(fs.readFileSync(path.join(root, relative), 'utf8'));
const manifest = read('package.json');
const registry = fs.readFileSync(path.join(root, 'src/modules.ts'), 'utf8');
const bundledBytes = fs.readFileSync(path.join(root, 'node_modules/expo/bundledNativeModules.json'));
const bundled = JSON.parse(bundledBytes);
const surfaces = registryEntries(root);
const packages = [...new Set(surfaces.map(name => name.startsWith('@') ? name.split('/').slice(0, 2).join('/') : name.split('/')[0]))];
for (const name of surfaces) if (!registry.includes(`'${name}'`)) throw new Error(`Missing registry import: ${name}`);
const registeredModules = packages.map(name => {
  const installed = read(`node_modules/${name}/package.json`);
  const configPath = path.join(root, 'node_modules', name, 'expo-module.config.json');
  const nativePlatforms = fs.existsSync(configPath) ? JSON.parse(fs.readFileSync(configPath, 'utf8')).platforms : null;
  return { name, requestedVersion: manifest.dependencies[name], installedVersion: installed.version, nativePlatforms, surfaces: surfaces.filter(surface => surface === name || surface.startsWith(`${name}/`)), status: 'registered; Android native/hardware behavior requires device validation' };
});
const bundleAudit = Object.entries(bundled).map(([name, sdkVersion]) => {
  if (packages.includes(name)) return { name, sdkVersion, decision: 'registered', evidence: `package.json dependency; src/modules.ts static import; node_modules/${name}/package.json` };
  const exclusion = bundleExclusions[name];
  if (!exclusion) throw new Error(`Unclassified SDK bundled package: ${name}`);
  const [decision, reason, evidence] = exclusion;
  return { name, sdkVersion, decision, reason, evidence };
});
for (const name of Object.keys(bundleExclusions)) if (!(name in bundled)) throw new Error(`Stale bundle exclusion: ${name}`);
const expoFeatureModules = packages.filter(name => name.startsWith('expo-') || name === '@expo/ui' || name === '@expo/vector-icons');
const inventory = {
  expo: manifest.dependencies.expo, platform: 'android',
  registeredPackageCount: packages.length,
  registeredExpoFeaturePackageCount: expoFeatureModules.length,
  registeredSurfaceCount: surfaces.length,
  customAdapters: [
    { name: 'eyg-widgets', exports: ['home', 'notification'], status: 'precompiled generic layout; widget/notification Android device behavior unverified' },
    { name: 'eyg-background', exports: ['define', 'list', 'get', 'result', 'cancel', 'forget', 'run', 'resetSlots'], status: 'durable source entrypoints; fresh VM per callback; cold restart host-tested; Android OS scheduling unverified' },
  ],
  registeredModules,
  bundledManifestSha256: crypto.createHash('sha256').update(bundledBytes).digest('hex'),
  bundleCoverage: { total: bundleAudit.length, registered: bundleAudit.filter(entry => entry.decision === 'registered').length, classifiedExcluded: bundleAudit.filter(entry => entry.decision !== 'registered').length, unclassified: 0 },
  bundleAudit,
  protocol: ['Expo', 'ExpoNextEvent', 'ExpoReply', 'ExpoRelease', 'ExpoView'],
  platformNotes: [
    'SDK58 expo-widgets includes Android widgets/custom notifications despite its iOS-oriented README; layouts need the widget compiler and declared Android provider configuration.',
    'SDK58 expo-symbols implements Android Material Symbols in JavaScript/assets although its native module config lists Apple.',
    'SDK58 expo-tracking-transparency exposes Android Advertising ID; its tracking permission prompts apply to iOS.',
    'expo-updates requires a configured updates URL/runtime and signed release build for remote updates; no update service is configured by default.',
    'Apple App Intents, native Apple authentication, glass effects, Live Photos and iOS Live Activities remain platform-specific.',
  ],
  limits: [
    'Registration covers package entrypoints and listed Android subpaths, not proof of every export behavior or native feature on hardware.',
    'React hooks are not imperative phone effects; call corresponding SDK functions or mount their exported components.',
    'ExpoView supports nested descriptor children; protected APIs still require Expo permission calls.',
    'eyg-widgets supplies a precompiled generic tree layout and declared EygWidget Android provider. Additional widget providers/layout code require a rebuild; runtime EYG callbacks cannot be serialized as widget worklets.',
    'Reanimated/Worklets UI-thread callbacks also require precompiled worklets; runtime EYG callbacks execute in the JavaScript host.',
    'eyg-background restores durable source entrypoints behind 16 synchronously defined TaskManager slots; each OS callback starts a fresh VM. Live continuation serialization is not implemented.',
    'Background slot identities survive forget to prevent stale delivery to another task; 16 historical names until verified resetSlots and JavaScript process restart.',
    'Synchronous dynamic callbacks use isolated pure EYG source with max10000 total VM steps, fixed4MiB allocator, 4096-byte source and64KiB input/output. Effects, references, structural equal and substring split/replace builtins are rejected.',
    'Google Maps, Stripe payments, push notifications and remote updates require provider/project configuration.',
    'Native hardware features and APK launch have not been validated unless separately recorded in validation.json.',
  ],
};
fs.writeFileSync(path.join(root, 'capabilities.json'), JSON.stringify(inventory, null, 2) + '\n');
console.log(JSON.stringify({ registeredPackages: packages.length, registeredExpoFeaturePackages: expoFeatureModules.length, registeredSurfaces: surfaces.length, bundledCoverage: inventory.bundleCoverage, deviceVerification: false }));
