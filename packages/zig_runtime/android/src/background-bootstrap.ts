import AsyncStorage from '@react-native-async-storage/async-storage';
import * as TaskManager from 'expo-task-manager';
import { requireNativeModule } from 'expo-modules-core';
import { Paths } from 'expo-file-system';
import { BackgroundTasks } from './background.mjs';
import { ExpoEffects } from './effects.mjs';

type NativeRuntime = {
  pureSync(request: string): string;
  create(): Promise<number>;
  evaluate(id: number, request: string): Promise<string>;
  resume(id: number, reply: string): Promise<string>;
  destroy(id: number): Promise<void>;
};
let registry: Record<string, unknown> | null = null;
const runtime = () => requireNativeModule<NativeRuntime>('EygRuntime');
const background = new BackgroundTasks({
  storage: AsyncStorage,
  taskManager: TaskManager,
  native: {
    create: () => runtime().create(),
    evaluate: (id: number, request: string) => runtime().evaluate(id, request),
    resume: (id: number, reply: string) => runtime().resume(id, reply),
    destroy: (id: number) => runtime().destroy(id),
  },
  hostFactory: () => {
    if (!registry) throw new Error('Background module registry is not initialized');
    return new ExpoEffects(registry, null, 1024, { pure: (request: string) => runtime().pureSync(request) });
  },
  directory: Paths.document.uri,
});

// Import this module at global bundle initialization, then supply the completed
// registry. Fixed TaskManager dispatchers are already defined synchronously.
export function initializeBackground(modules: Record<string, unknown>) {
  registry = modules;
  return background.ready;
}
export const backgroundReady: Promise<void> = background.ready;
export const define = (settings: Record<string, unknown>) => background.define(settings);
export const list = () => background.list();
export const get = (name: string) => background.get(name);
export const result = (name: string) => background.result(name);
export const cancel = (name: string) => background.cancel(name);
export const forget = (name: string) => background.forget(name);
export const run = (name: string, data?: unknown) => background.run(name, data);
export const resetSlots = () => background.resetSlots();
