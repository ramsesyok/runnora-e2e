package main

import (
	"math"
	"testing"
)

func TestHeadOnCollisionThenWallReflection(t *testing.T) {
	sim := simulation{
		area: area{0, 8, 0, 8, 0, 2},
		objects: []object{
			{id: 101, position: position{2, 4, 1}, vx: 1},
			{id: 102, position: position{6, 4, 1}, vx: -1},
		},
	}
	var nextID, hits, reflections int64
	for step := 0; step < 8; step++ {
		for _, ev := range advance(&sim, &nextID) {
			switch ev.kind {
			case 1:
				hits++
				if len(ev.objects) != 2 || ev.objects[0] != 101 || ev.objects[1] != 102 || math.Abs(ev.position.x-4) > 1e-9 {
					t.Fatalf("unexpected collision: %+v", ev)
				}
			case 2:
				reflections++
			default:
				t.Fatalf("unexpected event: %+v", ev)
			}
		}
		for _, o := range sim.objects {
			if o.position.x < radius || o.position.x > 8-radius || o.position.y < radius || o.position.y > 8-radius {
				t.Fatalf("object escaped area at step %d: %+v", step+1, o)
			}
		}
	}
	if hits != 1 || reflections < 2 {
		t.Fatalf("hits=%d, reflections=%d; want one collision and two wall reflections", hits, reflections)
	}
}

func TestDifferentZPlanesDoNotCollide(t *testing.T) {
	sim := simulation{
		area: area{0, 8, 0, 8, 0, 4},
		objects: []object{
			{id: 1, position: position{2, 4, 1}, vx: 1},
			{id: 2, position: position{6, 4, 2}, vx: -1},
		},
	}
	var nextID int64
	for step := 0; step < 4; step++ {
		for _, ev := range advance(&sim, &nextID) {
			if ev.kind == 1 {
				t.Fatal("objects on different Z planes collided")
			}
		}
	}
}
