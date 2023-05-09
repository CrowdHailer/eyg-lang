package fern

import (
	"fmt"

	"github.com/gdamore/tcell/v2"
)

// TODO lookup all text box features
// move cursor to beginning of element - maybe have a state that is at path
type Editor struct {
	// ScrollX and Y for when it's too large
}

func Draw(screen tcell.Screen, source Node, selected []int) ([][][]int, [][]int) {
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
	source.draw(screen, &Point{}, selected, &grid, []int{}, &g2, &index, 0, false, false)
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
	s.SetCursorStyle(tcell.CursorStyleSteadyBar)
	s.ShowCursor(cursor.X, cursor.Y)

	source = Source()
	var selected []int
	grid, g2 := Draw(s, source, selected)

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
					if selected == nil {
						path := grid[cursor.X][cursor.Y]
						target, c, err := zipper(source, path)
						if err != nil {
							fmt.Println(err.Error())
						}
						changed := false
						switch ev.Rune() {
						case 'e':
							source = c(Let{"", Vacant{""}, target})
							changed = true
						case 'r':
							if _, ok := target.(Vacant); ok {
								source = c(Empty{})
							} else {
								source = c(Call{Call{Extend{""}, Vacant{""}}, target})
							}
							changed = true
						case 't':
							if _, ok := target.(Vacant); ok {
								source = c(Tag{})
							} else {
								source = c(Call{Tag{""}, target})
							}
							changed = true
						case 'i':
							selected = grid[cursor.X][cursor.Y]
							changed = true
						case 'd':
							source = c(Vacant{})
							changed = true
						case 'c':
							source = c(Call{target, Vacant{}})
							changed = true
						case 'x':
							if _, ok := target.(Vacant); ok {
								source = c(Empty{})
							} else {
								source = c(Call{Call{Cons{}, Vacant{""}}, target})
							}
							changed = true
						case 'v':
							source = c(Var{"new_v"})
							changed = true
						case 'b':
							source = c(String{""})
							changed = true
						}
						if changed {
							s.Clear()
							grid, g2 = Draw(s, source, selected)
							render(s, *cursor, w, h, grid, g2)
						}
					} else {
						path := grid[cursor.X][cursor.Y]
						target, c, err := zipper(source, path)
						if err != nil {
							fmt.Println(err.Error())
						}
						switch t := target.(type) {
						case String:
							new := String{t.value + string(ev.Rune())}
							source = c(new)
							s.Clear()
							cursor.X += 1
							grid, g2 = Draw(s, source, selected)
							render(s, *cursor, w, h, grid, g2)
						default:
							panic("not a node I expected")
						}
					}
				case tcell.KeyEscape, tcell.KeyEnter, tcell.KeyCtrlC:
					if selected == nil {
						close(quit)
						return
					}
					selected = nil
					s.Clear()
					grid, g2 = Draw(s, source, selected)
					render(s, *cursor, w, h, grid, g2)
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
