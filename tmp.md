let s (^Read_Source "./saved/saved.json")
let db (cozo s)
(std.string.length db)

(^Await (^LoadDB "[]"))
(^Await (^QueryDB "?[] <- [['hello', 'world!']]"))
(^Await (^QueryDB "?[label] := *eav[id, 'label', label], *eav[id, 'expression', 'Let'],"))

(let stop (serve 8080 (fn _ (browser.continue (fn _ (^Log "hey"))))))

(let client (netlify.auth 1))
(.status (expect (client.deploy client.scratch (spa (fn x x)))))

(.status (expect (client.deploy client.scratch [(file "index.html" (app reactive.app)) (file "_headers" _headers)])))

(let client (fly.auth "test"))
<!-- need to capture environment here -->
(client.update_machine fly.app fly.machine (fn _ (app simple)))


(facilities.dnsimple.auth 1)

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

