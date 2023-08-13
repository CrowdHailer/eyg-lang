package main

import (
	"fmt"
	"io"
	"net/http"
	"time"
)

// really only returns value or error
func external(label string, lift Value) C {
	if label == "Log" {
		fmt.Printf("LOG: %s\n", lift.debug())
		return &Empty{}
	}
	if label == "Alert" {
		fmt.Printf("ALERT: %s\n", lift.debug())
		return &Empty{}
	}
	if label == "Wait" {
		m, ok := lift.(*Integer)
		if !ok {
			return &Error{&NotAnInteger{lift}}
		}
		time.Sleep(time.Duration(m.value) * time.Millisecond)
		return &Empty{}
	}
	if label == "Await" {
		return lift
	}
	if label == "HTTP" {
		// Can I make this less repetitive
		m, ok := field(lift, "method")
		if !ok {
			return &Error{&MissingField{"method", lift}}
		}
		method, ok := m.(*Tag)
		if !ok {
			return &Error{&NotATagged{m}}
		}
		fmt.Println(method.label)
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
		req, err := http.NewRequest("GET", fmt.Sprintf("https://%s%s", host.value, path.value), nil)
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
	}

	return &Error{&UnhandledEffect{label, lift}}
}
