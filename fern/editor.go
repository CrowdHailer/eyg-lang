package fern

import (
	"encoding/json"
	"fmt"

	"github.com/gdamore/tcell/v2"
)

// TODO lookup all text box features
// move cursor to beginning of element - maybe have a state that is at path
// TODO undo
// Python tui thing https://github.com/Textualize/textual#about
// Don't wrap just go over the edge if content exists
type Editor struct {
	// ScrollX and Y for when it's too large
}

func Draw(screen tcell.Screen, source Node, selected []int) ([][][]int, [][]ref) {
	w, h := screen.Size()
	grid := make([][][]int, w)
	for x := range grid {
		grid[x] = make([][]int, h)

	}
	g2 := make([][]ref, w)
	for x := range g2 {
		g2[x] = make([]ref, h)

	}
	index := 0
	source.draw(screen, &Point{}, selected, &grid, []int{}, &g2, &index, 0, false, false)
	return grid, g2
}

func New(s tcell.Screen, store Store) {
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

	raw, err := store.Load()
	if err != nil {
		fmt.Println(err.Error())
		return
	}

	source, err = decode(raw)
	if err != nil {
		fmt.Println(err.Error())
		return
	}

	var selected []int
	grid, g2 := Draw(s, source, selected)
	var yanked Node = Vacant{}

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
						case 'q':
							data, err := json.Marshal(source)
							if err != nil {
								fmt.Println(err.Error())
							}
							err = store.Save(data)
							if err != nil {
								fmt.Println(err.Error())
							}
						case 'w':
							source = c(Call{Vacant{""}, target})
							changed = true
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
						case 'y':
							yanked = target
						case 'Y':
							source = c(yanked)
							changed = true
							// u -> don't really use and delete in labels might make more sense
						case 'i':
							// return update fn from path/node use in the saving state
							// always needs to be string even for number
							selected = grid[cursor.X][cursor.Y]
							changed = true
						case 'o':
							// always have a target because the target should be a variable never a tail
							source = c(Call{Call{Overwrite{""}, Vacant{""}}, target})
							// unchanged false can be part of default maybe as i keys don't change source
							changed = true
						case 'p':
							// could always call if value given
							source = c(Perform{})
							changed = true
						case 'd':
							source = c(Vacant{})
							changed = true
						case 'f':
							source = c(Fn{"", target})
							changed = true
						case 'g':
							if _, ok := target.(Vacant); ok {
								source = c(Select{})
							} else {
								source = c(Call{Select{""}, target})
							}
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
							source = c(Var{""})
							changed = true
						case 'b':
							source = c(String{" "})
							changed = true
						}
						if changed {
							s.Clear()
							grid, g2 = Draw(s, source, selected)
							render(s, *cursor, w, h, grid, g2)
						}
					} else {

						path := grid[cursor.X][cursor.Y]
						offset := g2[cursor.X][cursor.Y].offset
						if offset < 0 {
							break
						}
						target, c, err := zipper(source, path)
						if err != nil {
							fmt.Println(err.Error())
						}
						var new Node
						switch t := target.(type) {
						case Fn:
							param := t.param[:offset] + string(ev.Rune()) + t.param[offset:]
							new = Fn{param, t.body}
						case Var:
							label := t.label[:offset] + string(ev.Rune()) + t.label[offset:]
							new = Var{label}
						case Let:
							label := t.label[:offset] + string(ev.Rune()) + t.label[offset:]
							new = Let{label, t.value, t.then}
						case Vacant:
							new = Vacant{t.note + string(ev.Rune())}
						case String:
							value := t.value[:offset] + string(ev.Rune()) + t.value[offset:]
							new = String{value}
						case Extend:
							label := t.label[:offset] + string(ev.Rune()) + t.label[offset:]
							new = Extend{label}
						case Select:
							label := t.label[:offset] + string(ev.Rune()) + t.label[offset:]
							new = Select{label}
						case Overwrite:
							label := t.label[:offset] + string(ev.Rune()) + t.label[offset:]
							new = Overwrite{label}
						case Perform:
							label := t.label[:offset] + string(ev.Rune()) + t.label[offset:]
							new = Perform{label}
						case Handle:
							label := t.label[:offset] + string(ev.Rune()) + t.label[offset:]
							new = Handle{label}
						default:
							panic("not a node I expected")
						}
						source = c(new)
						s.Clear()
						cursor.X += 1
						grid, g2 = Draw(s, source, selected)
						render(s, *cursor, w, h, grid, g2)
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

func render(s tcell.Screen, cursor Point, w, h int, grid [][][]int, g2 [][]ref) {
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
