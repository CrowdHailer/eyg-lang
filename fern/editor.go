package fern

import "github.com/gdamore/tcell/v2"

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

func Draw(screen tcell.Screen, source Node) [][][]int {
	w, h := screen.Size()
	grid := make([][][]int, w)
	for x := range grid {
		grid[x] = make([][]int, h)

	}
	source.Draw(screen, &Point{}, &grid, []int{}, 0, false)
	return grid
}
