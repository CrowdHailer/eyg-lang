package main

import (
	"fmt"
	"os"

	"github.com/gdamore/tcell/v2"
	"github.com/midas-framework/project_wisdom/fern"
)

func main() {
	tcell.SetEncodingFallback(tcell.EncodingFallbackASCII)
	s, e := tcell.NewScreen()
	if e != nil {
		fmt.Fprintf(os.Stderr, "%v\n", e)
		os.Exit(1)
	}
	if e = s.Init(); e != nil {
		fmt.Fprintf(os.Stderr, "%v\n", e)
		os.Exit(1)
	}
	w, h := s.Size()

	if w == 0 || h == 0 {
		return
	}

	s.SetStyle(tcell.StyleDefault)
	s.Clear()
	fern.New(s)
}
