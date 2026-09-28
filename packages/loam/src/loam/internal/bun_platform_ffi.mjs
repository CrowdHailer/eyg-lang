export async function waitForRedirect(port) {
  let resolve;
  const urlPromise = new Promise((res) => { resolve = res; });

  const server = globalThis.Bun.serve({
    port: port,
    fetch: (req) => {
      resolve(req.url);
      return new Response("OK");
    }
  });
  console.log("Listening on port", server.port);
  const url = await urlPromise;
  
  server.stop();
  return url;
}