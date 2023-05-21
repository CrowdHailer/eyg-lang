# Website for Eyg

```
docker-compose run --workdir /opt/app -p 5000:5000 editor bash
```
```
npm i -g sirv-cli
(cd eyg; gleam format && gleam build && npx rollup -f iife -i ./public/easel.js -o ../website/build/easel.js) && (cd website; cp -R public/* build/ && sirv ./build --dev --host 0.0.0.0 --port 5000)
```

What is best practise for make files bin scripts in a mono repo?