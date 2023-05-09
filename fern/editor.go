package fern

import (
	"fmt"

	"github.com/gdamore/tcell/v2"
)

type Editor struct {
	// ScrollX and Y for when it's too large
}

// type point struct {
// 	x int
// 	y int
// }

// func Lookup(x, y int, paths map[point][]int) {
// 	path, ok := paths[point{x, y}]
// 	if !ok {
// 		panic("out of range")
// 	}
// }

//

func Draw(screen tcell.Screen, source Node) ([][][]int, [][]int) {
	w, h := screen.Size()
	grid := make([][][]int, w)
	for x := range grid {
		grid[x] = make([][]int, h)

	}
	g2 := make([][]int, w)
	for x := range g2 {
		g2[x] = make([]int, h)

	}
	index := 0
	source.draw(screen, &Point{}, &grid, []int{}, &g2, &index, 0, false, false)
	return grid, g2
}

func New(s tcell.Screen) {
	source := Source()
	w, h := s.Size()

	if w == 0 || h == 0 {
		return
	}

	s.SetStyle(tcell.StyleDefault)
	s.Clear()

	cursor := &Point{}

	s.SetCursorStyle(tcell.CursorStyleDefault)
	s.ShowCursor(cursor.X, cursor.Y)

	source = Source()
	grid, g2 := Draw(s, source)

	quit := make(chan struct{})
	go func() {
		for {
			ev := s.PollEvent()
			switch ev := ev.(type) {
			case *tcell.EventKey:
				switch ev.Key() {

				case tcell.KeyLeft:
					cursor.X = Max(cursor.X-1, 0)
					render(s, *cursor, w, h, grid, g2)
				case tcell.KeyRight:
					cursor.X = Min(cursor.X+1, w-1)
					render(s, *cursor, w, h, grid, g2)
				case tcell.KeyUp:
					cursor.Y = Max(cursor.Y-1, 0)
					render(s, *cursor, w, h, grid, g2)
				case tcell.KeyDown:
					cursor.Y = Min(cursor.Y+1, h-1)
					render(s, *cursor, w, h, grid, g2)
				case tcell.KeyRune:
					switch ev.Rune() {
					case 'e':
						s.Clear()
						path := grid[cursor.X][cursor.Y]
						then, c, err := zipper(source, path)
						if err != nil {
							fmt.Println(err.Error())
						}
						source = c(Let{"x", Var{"hole"}, then})
						grid, g2 = Draw(s, source)
						render(s, *cursor, w, h, grid, g2)
					case 'c':
						s.Clear()
						path := grid[cursor.X][cursor.Y]
						_, c, err := zipper(source, path)
						if err != nil {
							fmt.Println(err.Error())
						}
						source = c(String{"new!!"})
						// source = Call{Var{"x"}, Var{"y"}}
						// cursor.Y = 10

						grid, g2 = Draw(s, source)
						render(s, *cursor, w, h, grid, g2)
					case 'x':
						// TODO Tail when vacant
						s.Clear()
						path := grid[cursor.X][cursor.Y]
						tail, c, err := zipper(source, path)
						if err != nil {
							fmt.Println(err.Error())
						}
						source = c(Call{Call{Cons{}, Var{"hole"}}, tail})
						grid, g2 = Draw(s, source)
						render(s, *cursor, w, h, grid, g2)
					case 'v':
						s.Clear()
						path := grid[cursor.X][cursor.Y]
						_, c, err := zipper(source, path)
						if err != nil {
							fmt.Println(err.Error())
						}
						source = c(Var{"new_v"})
						grid, g2 = Draw(s, source)
						render(s, *cursor, w, h, grid, g2)
					}
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

func render(s tcell.Screen, cursor Point, w, h int, grid [][][]int, g2 [][]int) {
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

// Max returns the larger of x or y.
func Max(x, y int) int {
	if x < y {
		return y
	}
	return x
}

// Min returns the smaller of x or y.
func Min(x, y int) int {
	if x > y {
		return y
	}
	return x
}
