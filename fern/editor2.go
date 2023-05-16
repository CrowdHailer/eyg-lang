package fern

import (
	"encoding/json"
	"fmt"

	"github.com/gdamore/tcell/v2"
)

// maybe panel is a term for what we have
// app
// app.run
// bubbel tea call it program

// I think we should call app that takes over the terminal
// TTY teletypewriter
// Screen.takeover
// App.Run

// Panel. <- is this just the shape
// start without code so we can show a loading screen

//
// editor.new(size: point)
// set source
// TODO!!!!! separation of screen from editor
// TODO!!! separate edit panel from terminal application stuff
// TODO start app with rendeirng of code
// block out tests that don't work and start editing

func Run(s tcell.Screen, store Store) error {
	w, h := s.Size()

	if w == 0 || h == 0 {
		return fmt.Errorf("zero sized screen")
	}

	s.SetStyle(tcell.StyleDefault)

	raw, err := store.Load()
	if err != nil {
		return err
	}

	source, err := decode(raw)
	if err != nil {
		return err
	}

	// editor will always have code, app might be in loading state
	editor := NewEditor(w, h, source)
	for {

		// TODO need to change this to a function that returns useful display position
		// index to coordinate
		// for i, r := range editor.page.buffer {
		// 	// quicker ways might be to do all indexes to coordinate first
		// 	inCode := editor.page.coordinates[i]
		// 	inPage := Coordinate{inCode.X - editor.shift.X, inCode.Y - editor.shift.Y}
		// 	s.SetContent(inPage.X, inPage.Y, r.character, []rune{}, tcell.StyleDefault)
		// }
		// Don't check error as zero value is fine
		for i := 0; i < editor.size.X; i++ {
			x := editor.shift.X + i
			for j := 0; j < editor.size.Y; j++ {
				y := editor.shift.Y + j
				if x >= editor.page.size.X || y >= editor.page.size.Y {
					s.SetContent(x, y, ' ', []rune{}, tcell.StyleDefault)
					continue
				}
				r := editor.page.lookup[x][y]
				if r == nil {
					s.SetContent(i, j, ' ', []rune{}, tcell.StyleDefault)
					continue
				}
				s.SetContent(i, j, r.character, []rune{}, r.style)
			}

		}

		s.ShowCursor(
			editor.position.X-editor.shift.X,
			editor.position.Y-editor.shift.Y,
		)
		s.Show()
		ev := s.PollEvent()
		switch ev := ev.(type) {
		case *tcell.EventKey:
			switch ev.Key() {
			case tcell.KeyLeft:
				editor.moveCursor(Coordinate{-1, 0})
			case tcell.KeyRight:
				editor.moveCursor(Coordinate{1, 0})
			case tcell.KeyUp:
				editor.moveCursor(Coordinate{0, -1})
			case tcell.KeyDown:
				editor.moveCursor(Coordinate{0, 1})
			case tcell.KeyHome:
				editor.moveCursor(Coordinate{-editor.size.X, 0})
			case tcell.KeyEnd:
				editor.moveCursor(Coordinate{editor.size.X, 0})
			case tcell.KeyPgUp:
				editor.moveCursor(Coordinate{0, -editor.size.Y})
			case tcell.KeyPgDn:
				editor.moveCursor(Coordinate{0, editor.size.Y})
			case tcell.KeyRune:
				editor.keyPress(ev.Rune())
			case tcell.KeyEnter:
				editor.lineBelow()
				// What is Backspace (not 2)
			case tcell.KeyBackspace2:
				editor.deleteCharachter()
			case tcell.KeyCtrlW:
				// Is there a transform primitive
				editor.callWith()
			case tcell.KeyCtrlE:
				// Is there a transform primitive
				editor.assignTo()
			case tcell.KeyCtrlS:
				data, err := json.Marshal(editor.source)
				if err != nil {
					panic(err.Error())
				}
				err = store.Save(data)
				if err != nil {
					panic(err.Error())
				}
			case tcell.KeyCtrlD:
				editor.deleteTarget()
			case tcell.KeyCtrlF:
				editor.function()
			case tcell.KeyCtrlL:
				s.Sync()
			case tcell.KeyEscape, tcell.KeyCtrlC:
				return nil
			}
		}
		// TODO default
	}
}

type editor struct {
	size  Coordinate
	shift Coordinate
	// position in page of code
	position Coordinate
	source   Node
	// cache
	page page
	info map[string]int
}

// TODO block actions by going to start of line

func NewEditor(w, h int, source Node) editor {
	size := Coordinate{w, h}

	e := editor{size: size}
	e.updateSource(source, []int{}, 0)
	return e
}

func (e *editor) updateSource(source Node, focus []int, offset int) {
	rendered, info := Print(source)
	page := NewPage(rendered)
	start := info[pathToString(focus)]
	cursor := page.coordinates[start+offset]
	e.position = cursor
	e.source = source
	e.page = page
	e.info = info
	e.updateView()
}

func (e *editor) moveCursor(step Coordinate) {
	x := e.position.X + step.X
	e.position.X = Min(Max(0, x), e.page.size.X)

	y := e.position.Y + step.Y
	e.position.Y = Min(Max(0, y), e.page.size.Y)

	e.updateView()
}

func (e *editor) updateView() {
	if overflow := e.position.X - (e.size.X + e.shift.X) + 1; overflow > 0 {
		e.shift.X += overflow
	}
	if overflow := e.position.X - e.shift.X; overflow < 0 {
		e.shift.X += overflow
	}
	if overflow := e.position.Y - (e.size.Y + e.shift.Y) + 1; overflow > 0 {
		e.shift.Y += overflow
	}
	if overflow := e.position.Y - e.shift.Y; overflow < 0 {
		e.shift.Y += overflow
	}
}

func (e *editor) keyPress(ch rune) {
	r := e.page.lookup[e.position.X][e.position.Y]
	if r == nil {
		return
	}
	target, build, err := zipper(e.source, r.path)
	if err != nil {
		panic("erorr making the zipper")
	}

	new, subPath, offset := target.keyPress(ch, r.offset)
	s := build(new)
	e.updateSource(s, append(r.path, subPath...), offset)
	// Should be safe as movement limited to bounding box
}

func (e *editor) lineBelow() {
	var found rendered
	for i := 0; i < 100; i++ {
		r := e.page.lookup[i][e.position.Y]
		if r != nil {
			found = *r
			break
		}
	}
	target, build, err := zipper(e.source, found.path)
	if err != nil {
		panic("erorr making the zipper")
	}
	switch t := target.(type) {
	case Let:
		new := Let{t.label, t.value, Let{"", Vacant{}, t.then}}
		s := build(new)
		e.updateSource(s, append(found.path, 1), 0)
	default:
		new := Let{"", target, Vacant{}}
		s := build(new)
		e.updateSource(s, append(found.path, 1), 0)
	}
}

func (e *editor) deleteCharachter() {
	r := e.page.lookup[e.position.X][e.position.Y]
	if r == nil {
		return
	}
	target, build, err := zipper(e.source, r.path)
	if err != nil {
		panic("erorr making the zipper")
	}

	new, subPath, offset := target.deleteCharachter(r.offset)
	s := build(new)
	e.updateSource(s, append(r.path, subPath...), offset)
}

func (e *editor) callWith() {
	r := e.page.lookup[e.position.X][e.position.Y]
	if r == nil {
		return
	}
	target, build, err := zipper(e.source, r.path)
	if err != nil {
		panic("erorr making the zipper")
	}

	switch t := target.(type) {
	case Let:
		new := Let{t.label, Call{Vacant{}, t.value}, t.then}
		s := build(new)
		e.updateSource(s, r.path, 0)
	default:
		new := Call{Vacant{}, t}
		s := build(new)
		e.updateSource(s, r.path, 0)
	}
}

func (e *editor) assignTo() {
	r := e.page.lookup[e.position.X][e.position.Y]
	if r == nil {
		return
	}
	target, build, err := zipper(e.source, r.path)
	if err != nil {
		panic("erorr making the zipper")
	}
	new := Let{"", target, Vacant{}}
	s := build(new)
	e.updateSource(s, r.path, 0)
}

func (e *editor) deleteTarget() {
	r := e.page.lookup[e.position.X][e.position.Y]
	if r == nil {
		return
	}
	target, build, err := zipper(e.source, r.path)
	if err != nil {
		panic("erorr making the zipper")
	}

	switch t := target.(type) {
	case Let:
		new := t.then
		s := build(new)
		e.updateSource(s, r.path, 0)
	default:
		new := Vacant{}
		s := build(new)
		e.updateSource(s, r.path, 0)
	}
}

func (e *editor) function() {
	r := e.page.lookup[e.position.X][e.position.Y]
	if r == nil {
		return
	}
	target, build, err := zipper(e.source, r.path)
	if err != nil {
		panic("erorr making the zipper")
	}

	switch t := target.(type) {
	case Let:
		new := Let{t.label, Fn{"", t.value}, t.then}
		s := build(new)
		e.updateSource(s, append(r.path, 0), 0)
	default:
		new := Fn{"", t}
		s := build(new)
		e.updateSource(s, r.path, 0)
	}
}

// Does TAB alway move to next linear index
