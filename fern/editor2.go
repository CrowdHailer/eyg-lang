package fern

import (
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

func Run(s tcell.Screen, store Store) {
	w, h := s.Size()

	if w == 0 || h == 0 {
		return
	}

	s.SetStyle(tcell.StyleDefault)

	raw, err := store.Load()
	if err != nil {
		fmt.Println(err.Error())
		return
	}

	source, err := decode(raw)
	if err != nil {
		fmt.Println(err.Error())
		return
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
					s.SetContent(x, y, ' ', []rune{}, tcell.StyleDefault)
					continue
				}
				s.SetContent(x, y, r.character, []rune{}, r.style)
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
			ctrl := ev.Modifiers()
			switch ev.Key() {
			case tcell.KeyLeft:
				editor.moveCursor(Coordinate{-1, 0})
			case tcell.KeyRight:
				editor.moveCursor(Coordinate{1, 0})
			case tcell.KeyUp:
				editor.moveCursor(Coordinate{0, -1})
			case tcell.KeyDown:
				editor.moveCursor(Coordinate{0, 1})
			case tcell.KeyRune:
				editor.keyPress(ev.Rune())
			case tcell.KeyEnter:
				fmt.Println(ctrl)
				editor.lineBelow()
			case tcell.KeyEscape, tcell.KeyCtrlC:
				return
			case tcell.KeyCtrlL:
				s.Sync()
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

// TODO grid lookup from inpage
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
}

func (e *editor) moveCursor(step Coordinate) {
	x := e.position.X + step.X
	if 0 <= x && x < e.page.size.X {
		e.position.X = x
	}
	y := e.position.Y + step.Y
	if 0 <= y && y < e.page.size.Y {
		e.position.Y = y
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

// Does TAB alway move to next linear index
