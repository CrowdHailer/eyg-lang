# Website for Eyg

```
docker-compose run --workdir /opt/app -p 5000:5000 editor bash
```
```
npm i -g sirv-cli
(cd eyg; gleam format && gleam build && gleam run cli website && npx rollup -c rollup.config.js -f iife -i ./public/easel.js -o ../website/build/easel.js) && (cd website; cp -R public/* build/ && npx sirv ./build --dev --host 0.0.0.0 --port 5000)
```

What is best practise for make files bin scripts in a mono repo?

lenses etc
https://www.youtube.com/watch?v=geV8F59q48E


### Issues building the website.

Right now I blow the stack when evaluating json decoding.
I don't tail optimise in my eyg code but I also think the interpreter is not correctly tail call opimised

I can build the website with
```
(cd eyg; node --stack-size=2000 ./build/dev/javascript/eyg/gleam.main.mjs cli website)
```

there is also a gleam run cli fetch to demonstrate that fetching works

How do I catch an environment properly I'm not sure,
however I could ship an env in the response.

Pass list till env and then build up the value after

There is no clever capture the function with stuff inplace, instead we just have to pull std from a library
So just collect everything in the client is the only way forward

putting JSON in the embed program still blows the stack