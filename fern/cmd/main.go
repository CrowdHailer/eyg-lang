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

	cursor := &fern.Point{}

	s.SetCursorStyle(tcell.CursorStyleDefault)
	s.ShowCursor(cursor.X, cursor.Y)

	grid, g2 := fern.Draw(s, fern.Source())

	quit := make(chan struct{})
	go func() {
		for {
			ev := s.PollEvent()
			switch ev := ev.(type) {
			case *tcell.EventKey:
				switch ev.Key() {

				case tcell.KeyLeft:
					cursor.X -= 1
					render(s, *cursor, w, h, grid, g2)
				case tcell.KeyRight:
					cursor.X += 1
					render(s, *cursor, w, h, grid, g2)
				case tcell.KeyUp:
					cursor.Y -= 1
					render(s, *cursor, w, h, grid, g2)
				case tcell.KeyDown:
					cursor.Y += 1
					render(s, *cursor, w, h, grid, g2)
				case tcell.KeyEscape, tcell.KeyEnter, tcell.KeyCtrlC:
					close(quit)
					return
				case tcell.KeyCtrlL:
					s.Sync()
				default:
					fmt.Printf("%#v\n", ev.Key())
				}
			case *tcell.EventResize:
				s.Sync()
			}
		}
	}()
	<-quit
	s.Fini()
}

func render(s tcell.Screen, cursor fern.Point, w, h int, grid [][][]int, g2 [][]int) {
	s.ShowCursor(cursor.X, cursor.Y)
	for i := 0; i < w; i++ {
		s.SetContent(i+1, h-1, ' ', nil, tcell.StyleDefault)
	}
	for i, ch := range fmt.Sprintf("%#v", grid[cursor.X][cursor.Y]) {
		s.SetContent(i+1, h-1, ch, nil, tcell.StyleDefault)
	}
	for i := 0; i < w; i++ {
		s.SetContent(i+1, h-2, ' ', nil, tcell.StyleDefault)
	}
	for i, ch := range fmt.Sprintf("%d", g2[cursor.X][cursor.Y]) {
		s.SetContent(i+1, h-2, ch, nil, tcell.StyleDefault)
	}
	s.Show()
}
