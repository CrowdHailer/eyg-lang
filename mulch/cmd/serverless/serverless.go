package main

import (
	"context"
	_ "embed"
	"fmt"
	"io"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"
)

//go:embed source.eyg.json
var s string

func main() {
	fmt.Println(s)
	mux := http.NewServeMux()
	mux.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		io.WriteString(w, s)
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
