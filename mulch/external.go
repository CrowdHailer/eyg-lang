package mulch

import (
	"fmt"
	"io"
	"net/http"
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
		fmt.Println(method.Label)
		h, ok := field(lift, "host")
		if !ok {
			return &Error{&MissingField{"host", lift}}
		}
		host, ok := h.(*String)
		if !ok {
			return &Error{&NotAString{h}}
		}
		fmt.Println(host)
		p, ok := field(lift, "path")
		if !ok {
			return &Error{&MissingField{"path", lift}}
		}
		path, ok := p.(*String)
		if !ok {
			return &Error{&NotAString{p}}
		}
		fmt.Println(path)
		req, err := http.NewRequest("GET", fmt.Sprintf("https://%s%s", host.Value, path.Value), nil)
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
			// call root because we know always the right type
			// unhandled effect always possible
			value, fail := Eval(handler, &Stack{
				K:    &CallWith{Value: &String{"hello"}},
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
