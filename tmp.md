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
