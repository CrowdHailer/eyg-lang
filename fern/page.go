package fern

// Source code is rendered to a page.
// A page is stored linearly

type page struct {
	buffer      []rendered
	coordinates []Coordinate
	size        Coordinate
	lookup      [][]*rendered
}

func NewPage(buffer []rendered) page {
	// Need to include current charachter i.e. index + 1
	// always bump x so initial conditions are -1 for x
	coordinates := make([]Coordinate, len(buffer))

	x := -1
	y := 0
	newline := false

	maxX := 0
	maxY := 0
	for i, r := range buffer {
		if newline {
			x = 0
			y += 1
			newline = false
		} else {
			x += 1
		}
		if r.character == '\n' {
			newline = true
		}
		coordinates[i] = Coordinate{x, y}
		maxX = Max(maxX, x)
		maxY = Max(maxY, y)
	}
	size := Coordinate{}
	if maxX != 0 {
		size.X = maxX + 1
		size.Y = maxY + 1
	}
	// lookup goes from grid to rendered
	lookup := make([][]*rendered, size.X)
	for x := range lookup {
		lookup[x] = make([]*rendered, size.Y)
	}
	for i, r := range buffer {
		// something silly with go references
		r := r
		c := coordinates[i]
		lookup[c.X][c.Y] = &r
	}
	return page{buffer, coordinates, size, lookup}
}
