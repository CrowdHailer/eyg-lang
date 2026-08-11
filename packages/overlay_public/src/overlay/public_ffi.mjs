export function ollamaApiKey() {
  return import.meta.env.OLLAMA_API_KEY || "";
}

export function isDevelopment() {
  return import.meta.env.DEV;
}
