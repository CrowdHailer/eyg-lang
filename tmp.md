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


(let client (facilities.google.auth 1))
(client.send "peter@petersaxton.uk" "somemessage")
(client.events "2023-10-10T00:00:00Z")
((.events (facilities.google.auth 1)) "2023-10-10T00:00:00Z") 


From: peterhsaxton@gmail.com
To: some@one.com
Content-Type: text/html; charset=utf-8

hello there
