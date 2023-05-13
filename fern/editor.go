package fern

import (
	"encoding/json"
	"fmt"

	"github.com/gdamore/tcell/v2"
)

// How do we handle typing or actions when the cursor is not on any element,
// This is because full grid allows motion of the tree that is not possible with tree navigation
// Make every point a no op by default

// After edits how do we put cursor in the right place, Option 1 we don't

// If we allow letters to be typed at the end of something how do we reference the square after particularly when it is blank

// How do we do highlight functions if for example you backspace at the beginning of a line

// Option 1 style of interaction
// In place text editing
//   - needs rerender or panel on each charachter press
// Single Box in the middle

// Option
// Explicit insert mode -> But you should end up in insert mode after inserting fn/binary etc
// typing ! for macros I don't want typo's i.e. lat! what does that do.

// Option implementation
// Tree lookup with offset
// Reverse lookup where grid takes us to element

// Panel of infinite charachter arrays or Wrapping

// TODO lookup all text box features
// move cursor to beginning of element - maybe have a state that is at path
// TODO undo number match
// TODO page overflow
// Undo BG color
// Don't edit outside of the correct box
// Python tui thing https://github.com/Textualize/textual#about
// Don't wrap just go over the edge if content exists
// Have a map of path to positions on the grid

// Draw needs to update cursor or return a grid of places
// How does one store the grid of places?
// Editing in place doesn't allow auto complete options etc
// Pulling up new window allows lensed edits
// i.e markdown syntax or something
// return grid position from render for cursor
// multi cursor returns lis
// view fragment with hash and pop upwards when expanding

// {r: 12, g: 10, b: 10} calling i on this has a lense
// How do we plug this together
// Deploy > Develop
// Can all edit's including of binary be in that view

// All
// arrows are a pain for collapsing

// Panic comes from the writing to grid/g2 which is out of range and set content just fails quietly
// Rendering code to a panel that is bigger than the screen doesn't allow us to pre allocate the array
// But if we use hashes it's not a problem

// CHOICE =========
// edit in place OR does "i" bring up an edit
// screen allows things like color pickers, which are not so useful in TUI
// in place is less jumping

// full typing idea was to use ! as a trigger for macro to do something. but this looks like VS Code style auto completes
// Shift enter for line above works in insert and command mode

// What does small reactivity a.la Solid look like. -> This is valuable for lots of performant UI's

// With my current style insert mode never start a new line unless multiline string
// can we edit just one line

// call update fn on element
// Should we assume one letter to the right when typing or not
// type handle!

// Pressing i on an element can create an in place box with a limit. But pressing i on a "(" after a var is going to be confusing

// React style diff by caching call to render with offset, there is no matrix transformations to efficiently move one square
// cache can be list for each element we have a single point or x/y

// Insert on Call can return correct child for each bracket

// How does language server automcomplete

// Right now anything calls a draw because text updates in place
type Editor struct {
	// ScrollX and Y for when it's too large
}

type mode string

const (
	command mode = "command"
	insert  mode = "insert"
)

func Draw(screen tcell.Screen, source Node, focus []int, mode mode) ([][][]int, [][]ref) {
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
	source.draw(screen, &Coordinate{}, focus, mode, &grid, []int{}, &g2, &index, 0, false, false)
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

	cursor := &Coordinate{}

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

	var focus []int
	mode := command
	grid, g2 := Draw(s, source, focus, mode)
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
					if mode == command {
						path := grid[cursor.X][cursor.Y]
						target, c, err := zipper(source, path)
						if err != nil {
							fmt.Println(err.Error())
						}
						changed := false
						// path to focus on
						// var focus []int
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
							// focus = append(path, 0)
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
							focus = grid[cursor.X][cursor.Y]
							mode = insert
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
						case 'h':
							source = c(Handle{})
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
						case 'n':
							source = c(Integer{0})
							changed = true
						case 'm':
							source = c(Call{Call{Case{}, Vacant{""}}, target})
							changed = true
						case 'M':
							source = c(NoCases{})
							changed = true

						}
						if changed {
							s.Clear()
							grid, g2 = Draw(s, source, focus, mode)
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
						grid, g2 = Draw(s, source, focus, mode)
						render(s, *cursor, w, h, grid, g2)
					}
				case tcell.KeyEscape, tcell.KeyEnter, tcell.KeyCtrlC:
					if mode == command {
						close(quit)
						return
					}
					mode = command
					s.Clear()
					grid, g2 = Draw(s, source, focus, mode)
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

func render(s tcell.Screen, cursor Coordinate, w, h int, grid [][][]int, g2 [][]ref) {
	s.ShowCursor(cursor.X, cursor.Y)
	for i := 0; i < w; i++ {
		s.SetContent(i, h-1, ' ', nil, tcell.StyleDefault)
	}
	for i, ch := range fmt.Sprintf("%#v", grid[cursor.X][cursor.Y]) {
		s.SetContent(i, h-1, ch, nil, tcell.StyleDefault)
	}
	for i := 0; i < w; i++ {
		s.SetContent(i, h-2, ' ', nil, tcell.StyleDefault)
	}
	for i, ch := range fmt.Sprintf("%d", g2[cursor.X][cursor.Y]) {
		s.SetContent(i, h-2, ch, nil, tcell.StyleDefault)
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
