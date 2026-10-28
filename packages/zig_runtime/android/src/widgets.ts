import { createWidget, createCustomNotification } from 'expo-widgets';
import { eygLayout } from './widget-layout.mjs';

// The widget provider is declared at build time in app.config.js. Foreground EYG
// programs can update its JSON props without attempting to serialize a VM closure.
export function home(initialProps: Record<string, unknown> = { text: 'EYG' }) {
  return createWidget('EygWidget', eygLayout, initialProps);
}
export function notification() {
  return createCustomNotification('EygNotification', eygLayout);
}
