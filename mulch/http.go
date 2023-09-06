package mulch

import (
	"context"
	"fmt"
	"net/http"
)

// https://stackoverflow.com/questions/53332667/how-to-notify-when-http-server-starts-successfully
func ListenAndServe(addr string, handler http.Handler) (func(context.Context) error, <-chan (error)) {
	stopped := make(chan error, 1)
	server := &http.Server{Addr: "0.0.0.0:8080", Handler: handler}
	go func() {
		err := server.ListenAndServe()
		if err != nil {
			fmt.Println(err.Error())
		}
		stopped <- err
	}()

	return server.Shutdown, stopped
}
