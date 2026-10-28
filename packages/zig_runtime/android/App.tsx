import React, { useEffect, useRef, useState } from 'react';
import { Alert, Button, ScrollView, StyleSheet, Text, TextInput, View } from 'react-native';
import { SafeAreaProvider, SafeAreaView } from 'react-native-safe-area-context';
import { requireNativeModule } from 'expo-modules-core';
import { Paths } from 'expo-file-system';
import { expoModules } from './src/modules';
import { backgroundReady } from './src/background-bootstrap';
// The effect boundary is ordinary JS so node can test it without native mocks.
// @ts-ignore
import { ExpoEffects } from './src/effects.mjs';
// @ts-ignore
import { runSession } from './src/session.mjs';
// @ts-ignore
import { renderView } from './src/views.mjs';

type NativeRuntime = {
  pureSync(request: string): string;
  create(): Promise<number>;
  evaluate(id: number, request: string): Promise<string>;
  resume(id: number, reply: string): Promise<string>;
  destroy(id: number): Promise<void>;
};
type ViewSpec = { id: string; module: string; component: string; props?: Record<string, unknown>; children?: unknown; ref?: boolean | string };
type RunContext = { controller: AbortController; host: ExpoEffects | null };
type NativeView = { owner: RunContext; child: React.ReactNode };

const initialProgram = `let result = perform Expo({
  module: "expo-battery",
  method: "getBatteryLevelAsync",
  args: []
})
result`;

function Workspace() {
  const [source, setSource] = useState(initialProgram);
  const [output, setOutput] = useState('Ready. Run EYG to evaluate with the Zig interpreter.');
  const [running, setRunning] = useState(false);
  const [views, setViews] = useState<Record<string, NativeView>>({});
  const activeRun = useRef<RunContext | null>(null);
  const mounted = useRef(true);
  useEffect(() => {
    mounted.current = true;
    return () => {
      mounted.current = false;
      const context = activeRun.current;
      activeRun.current = null;
      context?.controller.abort();
      context?.host?.close().catch(() => {});
    };
  }, []);

  function cancel() {
    const context = activeRun.current;
    if (!context) return;
    activeRun.current = null;
    context.controller.abort();
    context.host?.close().catch(() => {});
    setViews({});
    setOutput('Cancelled.');
    setRunning(false);
  }

  async function run() {
    if (activeRun.current) return;
    const context: RunContext = { controller: new AbortController(), host: null };
    activeRun.current = context;
    const current = () => mounted.current && activeRun.current === context && !context.controller.signal.aborted;
    setRunning(true);
    const host = new ExpoEffects(expoModules, {
      show: (spec: ViewSpec, emit: (topic: string, args: unknown[]) => void) => {
        if (!current()) throw new Error('Closed EYG run');
        if (!spec.id) throw new Error('Missing native view id');
        const child = renderView(spec, host, React.createElement, { rootStyle: styles.nativeView, emit, current });
        setViews(previous => current() ? { ...previous, [spec.id]: { owner: context, child } } : previous);
        return spec.id;
      },
      close: (id: string) => {
        if (mounted.current) setViews(previous => {
          if (previous[id]?.owner !== context) return previous;
          const next = { ...previous };
          delete next[id];
          return next;
        });
        return null;
      },
      clear: () => {
        if (mounted.current) setViews(previous => Object.fromEntries(
          Object.entries(previous).filter(([, view]) => view.owner !== context),
        ));
      },
    }, 1024, { pure: (request: string) => requireNativeModule<NativeRuntime>('EygRuntime').pureSync(request) });
    context.host = host;
    try {
      await backgroundReady;
      const native = requireNativeModule<NativeRuntime>('EygRuntime');
      const response = await runSession(native, host, source, (state: {label: string}) => { if (current()) setOutput(`Waiting for ${state.label}…`); }, undefined, { directory: Paths.document.uri }, context.controller.signal);
      if (current()) setOutput(JSON.stringify(response, null, 2));
    } catch (error) {
      if (current()) setOutput(error instanceof Error ? error.message : String(error));
    } finally {
      host.close().catch(() => {});
      if (activeRun.current === context) {
        activeRun.current = null;
        if (mounted.current) setRunning(false);
      }
    }
  }

  return <SafeAreaView style={styles.root}>
    <Text style={styles.title}>EYG · native Zig</Text>
    <Text style={styles.hint}>Phone APIs are explicit effects. Android permission prompts belong to the called Expo API.</Text>
    <TextInput accessibilityLabel="EYG program" multiline autoCapitalize="none" autoCorrect={false} value={source} onChangeText={setSource} editable={!running} style={styles.editor} />
    <View style={styles.actions}>
      <Button title={running ? 'Running…' : 'Run'} onPress={run} disabled={running} />
      <Button title="Cancel" disabled={!running} onPress={cancel} />
      <Button title="Effects" onPress={() => Alert.alert('Expo effects', 'Expo calls SDK methods; ExpoView mounts native components; ExpoNextEvent receives callbacks; ExpoReply answers async callbacks; ExpoRelease closes a native object. Use defer for SDK operations waiting for a callback. Call requestPermissionsAsync explicitly before protected APIs.')} />
    </View>
    {Object.entries(views).map(([id, view]) => <View key={id}>{view.child}</View>)}
    <ScrollView style={styles.output}><Text selectable style={styles.result}>{output}</Text></ScrollView>
  </SafeAreaView>;
}

export default function App() { return <SafeAreaProvider><Workspace /></SafeAreaProvider>; }
const styles = StyleSheet.create({
  root: { flex: 1, backgroundColor: '#101818', padding: 16 },
  title: { color: '#cef1ca', fontSize: 24, fontWeight: '600', marginBottom: 8 },
  hint: { color: '#a2b8ad', marginBottom: 12 },
  editor: { color: '#eaf5eb', backgroundColor: '#1b2924', borderRadius: 8, padding: 12, fontFamily: 'monospace', minHeight: 230, textAlignVertical: 'top' },
  actions: { flexDirection: 'row', justifyContent: 'space-around', marginVertical: 12 },
  output: { flex: 1 }, result: { color: '#eaf5eb', fontFamily: 'monospace' },
  nativeView: { width: '100%', height: 240 },
});
