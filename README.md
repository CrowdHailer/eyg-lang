# Eat Your Greens

**Experiments in building "better" languages and tools; for some measure of better.**

The name is a reference to the idea that eating your greens is good for you but the benefit is only realised at some later time. The idea in most these projects is to be very explicit about something, for example side effects. In doing so can we make tooling that is much better at giving insights about a program and in fact give back more than the initial constraints took away.

I have experimented with this priciple in building actor systems, datalog engines but most work is now focused on [Eyg](https://eyg.run). A language for programs that are fully explicit in all side-effects and therefore easier to run any where.

[![video introduction](https://videoapi-muybridge.vimeocdn.com/animated-thumbnails/image/4c0396bb-b75b-4e16-80fe-72a18e8dc725.gif?ClientID=vimeo-core-prod&Date=1690784024&Signature=e9dff0472fadd261013891cb2ab7d332486d3185)](https://vimeo.com/848449632?share=copy)

## Development

I post videos (2-10 min) of features as I develop them https://petersaxton.uk/log/.
They are mostly intended as notes for myself, but are the closest thing you will find to a documentation, or roadmap.

If you want to chat I hang out in the [Gleam Discord](https://gleam.run/community/).
If you to build anything in a safe functional expressive language, I would suggest use [Gleam](https://gleam.run/) instead. After all it's what I use.


```rs
let x = perform Ask({})
let y = 2
!int_add(x, y)
```

```js
let bind = (m, then) => {
  if !(m instanceof Eff) return then(m)
  let k = (x) => bind(m.k(x), then)
  return new Eff(m.label, m.value, k)
}

let perform = (label) => (value) => new Eff(label, value, (x) => x)

let handle = (label) => (handler) => (exec) => {
  let m = exec({})
  if !(m instanceof Eff) return m
  let k = (x) => do_handle(label, handler, m.k(x))
  if m.label == label return handler(m.value)(k)
  return new Eff(m.label, m.value, k)
} 

let  = {Ask: (x) => y}

bind(perform("Ask", {}), (x) => {
  let y = 2
  !int_add(x, y)
})
```