package mulch

import (
	"archive/zip"
	"bytes"
	"context"
	"fmt"
	"io"
	"net/http"
	"strings"
	"time"

	"github.com/skratchdot/open-golang/open"
)

func doLog(lift Value) C {
	fmt.Printf("LOG: %s\n", lift.Debug())
	return &Empty{}
}

func doHTTP(lift Value) C {
	// Can I make this less repetitive
	m, ok := Field(lift, "method")
	if !ok {
		return &Error{&MissingField{"method", lift}}
	}
	method, ok := m.(*Tag)
	if !ok {
		return &Error{&NotATagged{m}}
	}
	h, ok := Field(lift, "host")
	if !ok {
		return &Error{&MissingField{"host", lift}}
	}
	host, ok := h.(*String)
	if !ok {
		return &Error{&NotAString{h}}
	}
	p, ok := Field(lift, "path")
	if !ok {
		return &Error{&MissingField{"path", lift}}
	}
	path, ok := p.(*String)
	if !ok {
		return &Error{&NotAString{p}}
	}
	q, ok := Field(lift, "query")
	if !ok {
		return &Error{&MissingField{"query", lift}}
	}
	query := ""

	// TODO is this some none or empty string?
	if qstring, ok := q.(*String); ok && qstring.Value != "" {
		query = "?" + qstring.Value
	}
	// if !ok {
	// 	return &Error{&NotAString{q}}
	// }
	h, ok = Field(lift, "headers")
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
			k, ok := Field(item, "key")
			if !ok {
				return &Error{&MissingField{"key", lift}}
			}
			key, ok := k.(*String)
			if !ok {
				return &Error{&NotAString{k}}
			}
			v, ok := Field(item, "value")
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
	b, ok := Field(lift, "body")
	if !ok {
		return &Error{&MissingField{"body", lift}}
	}
	var reader io.Reader
	switch rbody := b.(type) {
	case *String:
		reader = strings.NewReader(rbody.Value)
	case *Binary:
		reader = bytes.NewReader(rbody.Value)
	default:
		return &Error{&NotAString{b}}
	}

	req, err := http.NewRequest(
		strings.ToUpper(method.Label),
		fmt.Sprintf("https://%s%s%s", host.Value, path.Value, query),
		reader)
	for _, h := range headers {
		req.Header.Set(h.k, h.v)
	}

	client := &http.Client{}
	resp, err := client.Do(req)
	if err != nil {
		return ErrorVariant(&String{Value: err.Error()})
	}

	return Ok(ResponseFromNative(resp))
}

// really only returns value or error
var Standard = map[string]func(Value) C{
	"Log": doLog,
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
		if p, ok := lift.(*Promise); ok {
			return <-p.Value
		}
		return lift
	},
	// httpbin testing
	"HTTP": doHTTP,
	"Serve": func(lift Value) C {
		p, ok := Field(lift, "port")
		if !ok {
			return &Error{&MissingField{"p", lift}}
		}
		port, ok := p.(*Integer)
		if !ok {
			return &Error{&NotAnInteger{p}}
		}
		// fmt.Println(port)
		h, ok := Field(lift, "handler")
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
				K: &CallWith{Value: RequestToLanguage(r)},
				Rest: &Done{External: map[string]func(Value) C{
					"Log":  doLog,
					"HTTP": doHTTP,
				},
				}})
			if fail != nil {
				w.WriteHeader(http.StatusInternalServerError)
				io.WriteString(w, fail.Reason())
				fmt.Println(fail.Reason())
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

		shutdown, _ := ListenAndServe(fmt.Sprintf(":%d", port.Value), mux)
		return &Defunc{"TODO serve", []Value{}, &Arity1{Impl: func(v Value, e E, k K) (C, E, K) {
			ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
			defer cancel()
			if err := shutdown(ctx); err != nil {
				return &Error{&MissingField{"TODO new error needed for external service", lift}}, e, k
			}
			return &Empty{}, e, k
		}}}
	},
	"Receive": func(lift Value) C {
		port, ok := lift.(*Integer)
		if !ok {
			return &Error{&NotAString{lift}}
		}
		shutdown, toHandle, error := ListenAndServeOnce(fmt.Sprintf(":%d", port.Value))
		ch := make(chan Value, 1)
		go func() {
			select {
			case in := <-toHandle:
				ch <- Ok((&Empty{}).
					Extend("request", RequestToLanguage(in.r)).
					Extend("reply", &Defunc{"TODO servereply", []Value{}, &Arity1{func(v Value, e E, k K) (C, E, K) {
						reply, ok := v.(*String)
						if !ok {
							in.done <- struct{}{}
							io.WriteString(in.w, "Error")
							return &Error{&NotAString{v}}, e, k
						}
						io.WriteString(in.w, reply.Value)
						in.done <- struct{}{}
						time.Sleep(1 * time.Second)
						shutdown(context.Background())
						return &Empty{}, e, k
					}}}))
			case err := <-error:
				ch <- ErrorVariant(&String{err.Error()})
			}
		}()
		return &Promise{ch}
	},
	// https://golang.cafe/blog/golang-zip-file-example.html
	"Zip": func(lift Value) C {
		buf := new(bytes.Buffer)
		zipWriter := zip.NewWriter(buf)
		fail := castList(lift, func(item Value) *Error {
			n, ok := Field(item, "name")
			if !ok {
				return &Error{&MissingField{"name", item}}
			}
			name, ok := n.(*String)
			if !ok {
				return &Error{&NotAString{n}}
			}
			c, ok := Field(item, "content")
			if !ok {
				return &Error{&MissingField{"content", item}}
			}
			content, ok := c.(*String)
			if !ok {
				return &Error{&NotAString{c}}
			}
			w1, err := zipWriter.Create(name.Value)
			if err != nil {
				panic(err)
			}

			if _, err := w1.Write([]byte(content.Value)); err != nil {
				panic(err)
			}

			return nil
		})
		zipWriter.Close()
		// not a string
		if fail != nil {
			return fail
		}
		// return &Binary{buf.Bytes()}
		return &String{buf.String()}
	},
	"Open": func(v Value) C {
		url, ok := v.(*String)
		if !ok {
			return &Error{&NotAString{v}}
		}
		open.Run(url.Value)
		return &String{Value: "opened"}
	},
}

func castList(value Value, then func(Value) *Error) *Error {
	list := value
	for {
		switch l := list.(type) {
		case *Cons:
			err := then(l.Item)
			if err != nil {
				return err
			}
			list = l.Tail
		case *Tail:
			return nil
		default:
			return &Error{&NotAList{list}}
		}
	}
}

func RequestToLanguage(r *http.Request) Value {
	var req Record = &Empty{}
	defer r.Body.Close()
	body, err := io.ReadAll(r.Body)
	if err != nil {
		fmt.Println(err.Error())
		panic("bad request data")
	}
	req = req.Extend("body", &String{Value: string(body)})
	req = req.Extend("headers", HeadersFromNative(r.Header))
	req = req.Extend("query", &String{Value: r.URL.RawQuery})
	req = req.Extend("path", &String{Value: r.URL.Path})
	// not r.URL.Host
	// https://stackoverflow.com/questions/42921567/what-is-the-difference-between-host-and-url-host-for-golang-http-request
	req = req.Extend("host", &String{Value: r.Host})
	req = req.Extend("scheme", &String{Value: r.URL.Scheme})
	req = req.Extend("method", &Tag{Label: r.Method, Value: &Empty{}})
	return req
}

func ResponseFromNative(r *http.Response) Value {
	var resp Record = &Empty{}
	body, err := io.ReadAll(r.Body)
	if err != nil {
		fmt.Println(err.Error())
		panic("bad request data")
	}
	resp = resp.Extend("body", &String{Value: string(body)})
	resp = resp.Extend("headers", HeadersFromNative(r.Header))
	resp = resp.Extend("status", &Integer{int32(r.StatusCode)})
	return resp
}

func HeadersFromNative(native http.Header) Value {
	var headers Value = &Tail{}
	for k, v := range native {
		var header Record = &Empty{}
		header = header.Extend("value", &String{Value: v[0]})
		header = header.Extend("key", &String{Value: k})
		headers = &Cons{Item: header, Tail: headers}
	}
	return headers
}
