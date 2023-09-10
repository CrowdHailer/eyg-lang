package mulch

import (
	"context"
	"fmt"
	"net/http"
)

// https://stackoverflow.com/questions/53332667/how-to-notify-when-http-server-starts-successfully
func ListenAndServe(addr string, handler http.Handler) (func(context.Context) error, <-chan (error)) {
	stopped := make(chan error, 1)
	server := &http.Server{Addr: addr, Handler: handler}
	go func() {
		err := server.ListenAndServe()
		if err != nil {
			fmt.Println(err.Error())
		}
		stopped <- err
	}()

	return server.Shutdown, stopped
}

type httpToHandle struct {
	r    *http.Request
	w    http.ResponseWriter
	done chan<- (struct{})
}

func ListenAndServeOnce(addr string) (func(context.Context) error, <-chan (httpToHandle), <-chan (error)) {
	handle := make(chan httpToHandle, 1)
	stopped := make(chan error, 1)

	server := &http.Server{Addr: addr}
	var handler http.HandlerFunc = func(w http.ResponseWriter, r *http.Request) {
		done := make(chan struct{}, 1)
		handle <- httpToHandle{r, w, done}
		<-done

	}
	server.Handler = handler
	go func() {
		err := server.ListenAndServe()
		if err != nil {
			fmt.Println(err.Error())
		}
		stopped <- err
	}()

	return server.Shutdown, handle, stopped

}
