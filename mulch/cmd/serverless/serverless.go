package main

import (
	"context"
	_ "embed"
	"fmt"
	"io"
	"mulch"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"
)

func main() {
	file := "/bin/source.eyg.json"
	json, err := os.ReadFile(file)
	if err != nil {
		fmt.Printf("error reading file '%s' \n", file)
		return
	}
	source, err := mulch.Decode(json)
	if err != nil {
		fmt.Printf("error decoding program source from '%s' \n", file)
		return
	}

	mux := http.NewServeMux()
	mux.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		value, fail := mulch.Eval(source, &mulch.Stack{K: &mulch.CallWith{Value: &mulch.Empty{}}, Rest: &mulch.Done{External: mulch.Standard}})
		if fail != nil {
			io.WriteString(w, fail.Reason())
			return
		}
		io.WriteString(w, value.Debug())
	})

	server := &http.Server{Addr: "0.0.0.0:8080", Handler: mux}
	go func() {
		err := server.ListenAndServe()
		if err != nil {
			fmt.Println(err.Error())
		}

	}()
	stop := make(chan os.Signal, 1)
	signal.Notify(stop, syscall.SIGINT, syscall.SIGTERM)

	<-stop

	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	if err := server.Shutdown(ctx); err != nil {
		fmt.Println(err.Error())
	}
}
