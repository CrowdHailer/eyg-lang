package main

import (
	_ "embed"
	"fmt"
	"io"
	"net/http"
)

//go:embed source.json
var s string

func main() {
	fmt.Println(s)
	mux := http.NewServeMux()
	mux.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		io.WriteString(w, s)
	})
	err := http.ListenAndServe("0.0.0.0:8080", mux)
	if err != nil {
		fmt.Println(err.Error())
	}
}
