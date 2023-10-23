## Recipe

let body (.body (expect (^Await (^HTTP (std.http.get "gleam.run")))))
let nodes (parse_html body)
let filter (std.list.filter (fn node (|Element (fn value (std.equal value.tag "a")) (fn _ false) node.node)))
(std.list.map as (fn a a.parent))

Need a filter_map -> maybe always this way

let body (.body (expect (^Await (^HTTP (std.http.path (std.http.get "www.simplyrecipes.com") "/copycat-chipotle-chicken-recipe-7967281")))))
let body (.body (expect (^Await (^HTTP (std.http.path (std.http.get "www.bbcgoodfood.com") "/recipes/naughty-chocolate-fudge-cake")))))
Note this needs the singular parser

let ld (.pre (expect (std.string.split_once (.post (expect (std.string.split_once (.post (expect (std.string.split_once body "ld+json"))) ">"))) "<")))
let parse (json.parse (json.list (json.object (json.field "@type" json.string json.end (fn f {field f})))))

https://www.bbcgoodfood.com/recipes/naughty-chocolate-fudge-cake
is  if an interesting functio
(std.list.filter (std.equal 2)  [2])

## Serving
let stop (serve 5000 (fn request (let _ (^Log request.path) (std.http.ok (std.http.html "hello")))))

let data (^Await (receive 5000 try_receive))
let stop (serve 5000 (static (projects.website.build "")))
let stop (serve 5000 (multi_tenent [{key "localhost:5000" value projects.laura}]))


let stop (serve 5000 ctrl.serve)
let stop (serve_page 5000 projects.counters)

## DB AST

let s (^Read_Source "./saved/saved.json")
let db (cozo.ast s)
(std.string.length db)

(^Await (^LoadDB db))
(^Await (^QueryDB "?[] <- [['hello', 'world!']]"))
(^Await (^QueryDB "?[label] := *eav[id, 'label', label], *eav[id, 'expression', 'Let'],"))
(^Await (^QueryDB "?[id, comment] := *eav[id, 'comment', comment], *eav[id, 'expression', 'Vacant'],"))
(^Await (^QueryDB "?[id] := *eav[id, a, attr], *eav[id, 'expression', 'Vacant'],"))

(^Await (^LoadDB (cozo.ast (std.capture file))))
(^Await (^QueryDB "?[id, attr] := *eav[id, 'label', attr], *eav[id, 'expression', 'Lambda'],"))


## Netlify
let client (facilities.netlify.auth {})
(.status (expect (^Await (client.deploy client.scratch [(file "index.html" "Yo!") (file "_headers" "/*.html\n  content-type: text/html")]))))
weird happenings with _headers
(file "_headers" _headers)])))
(.status (expect (client.deploy client.scratch (spa (fn x x)))))

(.status (expect (client.deploy client.scratch [(file "index.html" (app reactive.app)) (file "_headers" _headers)])))

## Fly
let client (facilities.fly.auth "local")
(^Await (client.update_machine facilities.fly.app facilities.fly.machine (fn _ "Yo")))
(client.update_machine facilities.fly.app facilities.fly.machine (fn _ (app simple)))

## DNSimple
(facilities.dnsimple.auth 1)
let client (facilities.dnsimple.auth {})
(expect (client.records dnsimple_me "petersaxton.uk"))


((fn x ((fn _ x.request) (x.reply "hello"))) (expect (^Await (^Receive 8080))))

(let server (fn req (!string_append "hey" req.query)))

(let server (fn req (std.string.append "hey" req.query)))

(let x (let _ (^Log "yo") (let _ (^Log "second"))))

List with effect types
OR
deploying a continuation
lisp docs, everything first class so partial cases, but need record syntax

```
// read_text and read_tag are arity2 curried functions

let update = fn (state, char) {
    match state {
        ReadText(params) -> read_text(params, char)
        ReadTag(params) -> read_tag(params, char)
    }
}

// extract call with char arg

let update = fn (state, char) {
    match state {
        ReadText(params) -> read_text(params)
        ReadTag(params) -> read_tag(params)
    }(char)
}

// return a function that accepts char later

let update = fn (state) {
    match state {
        ReadText(params) -> read_text(params)
        ReadTag(params) -> read_tag(params)
    }
}

// branches are function calls

let update = fn (state) {
    match state {
        ReadText read_text
        ReadTag read_tag
    }
}

// matches are first class

let update = match {
    ReadText read_text
    ReadTag read_tag
}
```

(let client (facilities.google.auth 1))
(client.send "peter@petersaxton.uk" "somemessage")
(client.events "2023-10-10T00:00:00Z")
((.events (facilities.google.auth 1)) "2023-10-10T00:00:00Z")


From: peterhsaxton@gmail.com
To: some@one.com
Content-Type: text/html; charset=utf-8

hello there
