package mulch

import (
	"fmt"
	"io"
	"net/http"
	"strings"
	"time"
)

// really only returns value or error
var Standard = map[string]func(Value) C{
	"Log": func(lift Value) C {
		fmt.Printf("LOG: %s\n", lift.Debug())
		return &Empty{}
	},

	"Alert": func(lift Value) C {
		fmt.Printf("ALERT: %s\n", lift.Debug())
		return &Empty{}
	},
	"Wait": func(lift Value) C {
		m, ok := lift.(*Integer)
		if !ok {
			return &Error{&NotAnInteger{lift}}
		}
		time.Sleep(time.Duration(m.Value) * time.Millisecond)
		return &Empty{}
	},
	"Await": func(lift Value) C {
		return lift
	},
	"HTTP": func(lift Value) C {
		// Can I make this less repetitive
		m, ok := field(lift, "method")
		if !ok {
			return &Error{&MissingField{"method", lift}}
		}
		method, ok := m.(*Tag)
		if !ok {
			return &Error{&NotATagged{m}}
		}
		h, ok := field(lift, "host")
		if !ok {
			return &Error{&MissingField{"host", lift}}
		}
		host, ok := h.(*String)
		if !ok {
			return &Error{&NotAString{h}}
		}
		p, ok := field(lift, "path")
		if !ok {
			return &Error{&MissingField{"path", lift}}
		}
		path, ok := p.(*String)
		if !ok {
			return &Error{&NotAString{p}}
		}
		h, ok = field(lift, "headers")
		if !ok {
			return &Error{&MissingField{"headers", lift}}
		}
		var headers []struct {
			k string
			v string
		}

	Outer:
		for {
			switch list := h.(type) {
			case *Cons:
				item := list.Item
				k, ok := field(item, "key")
				if !ok {
					return &Error{&MissingField{"key", lift}}
				}
				key, ok := k.(*String)
				if !ok {
					return &Error{&NotAString{k}}
				}
				v, ok := field(item, "value")
				if !ok {
					return &Error{&MissingField{"value", lift}}
				}
				value, ok := v.(*String)
				if !ok {
					return &Error{&NotAString{v}}
				}
				headers = append(headers, struct {
					k string
					v string
				}{k: key.Value, v: value.Value})
				h = list.Tail
			case *Tail:
				break Outer
			default:
				return &Error{&NotAList{h}}
			}
		}
		fmt.Printf("headers %#v\n", headers)
		b, ok := field(lift, "body")
		if !ok {
			return &Error{&MissingField{"body", lift}}
		}
		rbody, ok := b.(*String)
		if !ok {
			return &Error{&NotAString{b}}
		}

		req, err := http.NewRequest(
			strings.ToUpper(method.Label),
			fmt.Sprintf("https://%s%s", host.Value, path.Value),
			strings.NewReader(rbody.Value))
		for _, h := range headers {
			req.Header.Set(h.k, h.v)
		}

		if err != nil {
			fmt.Println(err.Error())
			panic("should be ok to make reqyest")
		}
		client := &http.Client{}
		resp, err := client.Do(req)
		if err != nil {
			fmt.Println(err.Error())
			panic("bad response")
		}

		defer resp.Body.Close()
		body, err := io.ReadAll(resp.Body)
		if err != nil {
			fmt.Println(err.Error())
			panic("bad response data")
		}

		return &String{string(body)}
	},
	"Serve": func(lift Value) C {
		p, ok := field(lift, "port")
		if !ok {
			return &Error{&MissingField{"p", lift}}
		}
		port, ok := p.(*Integer)
		if !ok {
			return &Error{&NotAString{p}}
		}
		// fmt.Println(port)
		h, ok := field(lift, "handler")
		if !ok {
			return &Error{&MissingField{"handler", lift}}
		}
		handler, ok := h.(*Closure)
		if !ok {
			return &Error{&NotAString{p}}
		}
		// fmt.Println(handler)

		mux := http.NewServeMux()
		mux.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {

			var req Record = &Empty{}
			body, err := io.ReadAll(r.Body)
			if err != nil {
				fmt.Println(err.Error())
				panic("bad response data")
			}
			req = req.Extend("body", &String{Value: string(body)})
			var headers Value = &Tail{}
			for k, v := range r.Header {
				var header Record = &Empty{}
				header = header.Extend("value", &String{Value: v[0]})
				header = header.Extend("key", &String{Value: k})
				headers = &Cons{Item: header, Tail: headers}
			}
			req = req.Extend("headers", headers)
			req = req.Extend("query", &String{Value: r.URL.RawQuery})
			req = req.Extend("path", &String{Value: r.URL.Path})
			// not r.URL.Host
			// https://stackoverflow.com/questions/42921567/what-is-the-difference-between-host-and-url-host-for-golang-http-request
			req = req.Extend("host", &String{Value: r.Host})
			req = req.Extend("scheme", &String{Value: r.URL.Scheme})
			req = req.Extend("method", &Tag{Label: r.Method, Value: &Empty{}})

			// call root because we know always the right type
			// unhandled effect always possible
			value, fail := Eval(handler, &Stack{
				K:    &CallWith{Value: req},
				Rest: &Done{External: nil},
			})
			if fail != nil {
				w.WriteHeader(http.StatusInternalServerError)
				io.WriteString(w, fail.Reason())
				return
			}
			raw, ok := value.(*String)
			if !ok {
				w.WriteHeader(http.StatusInternalServerError)
				io.WriteString(w, value.Debug())
				return
			}
			io.WriteString(w, raw.Value)
		})
		go func() {
			err := http.ListenAndServe(fmt.Sprintf(":%d", port.Value), mux)
			if err != nil {
				panic("no binding")
			}
			fmt.Println("listening")
		}()
		return &Empty{}
	},
}

// function to close server
// need
// run test
