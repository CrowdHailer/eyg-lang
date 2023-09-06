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
		value, fail := mulch.Eval(source, &mulch.Stack{
			K:    &mulch.CallWith{Value: mulch.RequestToLanguage(r)},
			Rest: &mulch.Done{External: mulch.Standard},
		})
		if fail != nil {
			io.WriteString(w, fail.Reason())
			return
		}
		io.WriteString(w, value.Debug())
	})

	// ignore stopped realy on log
	shutdown, _ := mulch.ListenAndServe("0.0.0.0:8080", mux)

	stop := make(chan os.Signal, 1)
	signal.Notify(stop, syscall.SIGINT, syscall.SIGTERM)

	<-stop

	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	if err := shutdown(ctx); err != nil {
		fmt.Println(err.Error())
	}
}
