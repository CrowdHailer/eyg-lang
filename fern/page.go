package fern

// Source code is rendered to a page.
// A page is stored linearly

func indexToCoordinate(buffer []rendered, index int) Coordinate {
	// can't use string because rendered
	// Need to include current charachter i.e. index + 1
	// always bump x so initial conditions are -1 for x
	x := -1
	y := 0
	newline := false
	for _, r := range buffer[:index+1] {
		if newline {
			x = 0
			y += 1
			newline = false
		} else {
			x += 1
		}
		if r.charachter == '\n' {
			newline = true
		}
	}
	return Coordinate{x, y}
}
