# overlay_web

## Development

```sh
gleam test
```

To use a context in the browser, run the public page against a hub:

```sh
cd ../overlay_public
EYG_HUB=http://localhost:8001 bun run dev
```

Open [localhost:5173/overlay/](http://localhost:5173/overlay/).
`EYG_HUB` selects the hub proxied by the development server for module and package lookups.
It defaults to `https://eyg.run`.
