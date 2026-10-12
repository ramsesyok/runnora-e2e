// simd streams a small collision simulation for runnora's gRPC E2E cases.
// The shared proto is compiled at startup, so protoc is not needed.
package main

import (
	"context"
	"crypto/rand"
	"flag"
	"fmt"
	"log"
	"math"
	"math/big"
	"net"
	"os"
	"os/signal"
	"path/filepath"
	"time"

	"github.com/bufbuild/protocompile"
	"google.golang.org/grpc"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"
	"google.golang.org/protobuf/reflect/protoreflect"
	"google.golang.org/protobuf/types/dynamicpb"
)

const radius = 0.5
const logsPerResponse = 5

type position struct{ x, y, z float64 }
type object struct {
	id       int64
	position position
	vx, vy   float64
}
type area struct{ xMin, xMax, yMin, yMax, zMin, zMax float64 }
type simulation struct {
	jobID   int64
	objects []object
	area    area
}
type event struct {
	id, kind int64
	objects  []int64
	position position
}
type simService interface{}
type server struct {
	messages map[string]protoreflect.MessageDescriptor
}

func main() {
	addr := flag.String("addr", "127.0.0.1:19091", "gRPC listen address")
	protoPath := flag.String("proto", "proto/simulation.proto", "shared proto path")
	flag.Parse()
	compiler := protocompile.Compiler{Resolver: &protocompile.SourceResolver{ImportPaths: []string{filepath.Dir(*protoPath)}}}
	files, err := compiler.Compile(context.Background(), filepath.Base(*protoPath))
	if err != nil {
		log.Fatalf("compile proto: %v", err)
	}
	file := files[0]
	svc := file.Services().ByName("SimService")
	if svc == nil {
		log.Fatal("SimService is missing")
	}
	s := &server{messages: make(map[string]protoreflect.MessageDescriptor)}
	for i := 0; i < file.Messages().Len(); i++ {
		m := file.Messages().Get(i)
		s.messages[string(m.Name())] = m
	}
	lis, err := net.Listen("tcp", *addr)
	if err != nil {
		log.Fatalf("listen: %v", err)
	}
	g := grpc.NewServer()
	g.RegisterService(&grpc.ServiceDesc{
		ServiceName: string(svc.FullName()),
		HandlerType: (*simService)(nil),
		Streams:     []grpc.StreamDesc{{StreamName: "ExecSimulation", Handler: s.execSimulation, ServerStreams: true}},
	}, s)
	go func() {
		ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt)
		defer stop()
		<-ctx.Done()
		g.GracefulStop()
	}()
	log.Printf("simulation gRPC server listening on %s", lis.Addr())
	if err := g.Serve(lis); err != nil {
		log.Fatalf("serve: %v", err)
	}
}

func (s *server) message(name string) *dynamicpb.Message {
	return dynamicpb.NewMessage(s.messages[name])
}
func field(m protoreflect.Message, name string) protoreflect.FieldDescriptor {
	return m.Descriptor().Fields().ByName(protoreflect.Name(name))
}
func number(m protoreflect.Message, name string) float64 { return m.Get(field(m, name)).Float() }
func integer(m protoreflect.Message, name string) int64  { return m.Get(field(m, name)).Int() }
func setFloat(m protoreflect.Message, name string, v float64) {
	m.Set(field(m, name), protoreflect.ValueOfFloat64(v))
}
func setInt(m protoreflect.Message, name string, v int64) {
	m.Set(field(m, name), protoreflect.ValueOfInt64(v))
}
func setMessage(m protoreflect.Message, name string, v protoreflect.Message) {
	m.Set(field(m, name), protoreflect.ValueOfMessage(v))
}
func appendMessage(m protoreflect.Message, name string, v protoreflect.Message) {
	m.Mutable(field(m, name)).List().Append(protoreflect.ValueOfMessage(v))
}
func finite(v float64) bool { return !math.IsNaN(v) && !math.IsInf(v, 0) }

func parseRequest(req protoreflect.Message) (simulation, error) {
	var sim simulation
	sim.jobID = integer(req, "job_id")
	if sim.jobID <= 0 {
		return sim, status.Error(codes.InvalidArgument, "job_id must be positive")
	}
	if !req.Has(field(req, "area")) {
		return sim, status.Error(codes.InvalidArgument, "area is required")
	}
	a := req.Get(field(req, "area")).Message()
	sim.area = area{number(a, "x_min"), number(a, "x_max"), number(a, "y_min"), number(a, "y_max"), number(a, "z_min"), number(a, "z_max")}
	b := sim.area
	for _, v := range []float64{b.xMin, b.xMax, b.yMin, b.yMax, b.zMin, b.zMax} {
		if !finite(v) {
			return sim, status.Error(codes.InvalidArgument, "area bounds must be finite")
		}
	}
	if b.xMax-b.xMin <= 2*radius || b.yMax-b.yMin <= 2*radius || b.zMax-b.zMin < 2*radius {
		return sim, status.Error(codes.InvalidArgument, "area bounds are reversed or too small")
	}
	inputs := req.Get(field(req, "objects")).List()
	if inputs.Len() == 0 || inputs.Len() > 32 {
		return sim, status.Error(codes.InvalidArgument, "objects must contain 1 to 32 items")
	}
	ids := make(map[int64]bool, inputs.Len())
	for i := 0; i < inputs.Len(); i++ {
		m := inputs.Get(i).Message()
		id, speed, direction := integer(m, "object_id"), number(m, "speed"), number(m, "direction")
		if id <= 0 || ids[id] {
			return sim, status.Error(codes.InvalidArgument, "object_id must be unique and positive")
		}
		ids[id] = true
		if !m.Has(field(m, "position")) {
			return sim, status.Error(codes.InvalidArgument, "position is required")
		}
		p := m.Get(field(m, "position")).Message()
		pos := position{number(p, "x"), number(p, "y"), number(p, "z")}
		if !finite(pos.x) || !finite(pos.y) || !finite(pos.z) || !finite(speed) || !finite(direction) || speed < 0 || speed > math.Min(b.xMax-b.xMin, b.yMax-b.yMin) {
			return sim, status.Error(codes.InvalidArgument, "object coordinates, speed and direction must be finite; speed must be within area size")
		}
		if pos.x < b.xMin+radius || pos.x > b.xMax-radius || pos.y < b.yMin+radius || pos.y > b.yMax-radius || pos.z < b.zMin+radius || pos.z > b.zMax-radius {
			return sim, status.Error(codes.InvalidArgument, "object is outside area")
		}
		radians := direction * math.Pi / 180
		sim.objects = append(sim.objects, object{id: id, position: pos, vx: speed * math.Cos(radians), vy: speed * math.Sin(radians)})
	}
	for i := range sim.objects {
		for j := i + 1; j < len(sim.objects); j++ {
			dx := sim.objects[j].position.x - sim.objects[i].position.x
			dy := sim.objects[j].position.y - sim.objects[i].position.y
			dz := sim.objects[j].position.z - sim.objects[i].position.z
			if dx*dx+dy*dy+dz*dz < 4*radius*radius-1e-9 {
				return sim, status.Error(codes.InvalidArgument, "objects overlap initially")
			}
		}
	}
	return sim, nil
}

func (s *server) execSimulation(_ interface{}, stream grpc.ServerStream) error {
	req := s.message("SimRequest")
	if err := stream.RecvMsg(req); err != nil {
		return err
	}
	sim, err := parseRequest(req.ProtoReflect())
	if err != nil {
		return err
	}
	choice, err := rand.Int(rand.Reader, big.NewInt(5))
	if err != nil {
		return status.Errorf(codes.Internal, "choose duration: %v", err)
	}
	steps := 8 + int(choice.Int64())
	ticker := time.NewTicker(40 * time.Millisecond)
	defer ticker.Stop()
	var nextEventID, hitCount int64
	logs := make([]protoreflect.Message, 0, logsPerResponse)
	for step := 1; step <= steps; step++ {
		select {
		case <-stream.Context().Done():
			return stream.Context().Err()
		case <-ticker.C:
		}
		events := advance(&sim, &nextEventID)
		for _, ev := range events {
			if ev.kind == 1 {
				hitCount++
			}
		}
		logs = append(logs, s.logEntry(sim, step, events))
		if len(logs) == logsPerResponse || step == steps {
			response := s.response(sim.jobID, step, steps, hitCount, logs)
			if err := stream.SendMsg(response); err != nil {
				return fmt.Errorf("send through step %d: %w", step, err)
			}
			logs = make([]protoreflect.Message, 0, logsPerResponse)
		}
	}
	return nil
}

func advance(sim *simulation, nextID *int64) []event {
	previous := make([]position, len(sim.objects))
	var events []event
	add := func(kind int64, ids []int64, p position) {
		*nextID = *nextID + 1
		events = append(events, event{id: *nextID, kind: kind, objects: ids, position: p})
	}
	for i := range sim.objects {
		o := &sim.objects[i]
		previous[i] = o.position
		o.position.x += o.vx
		o.position.y += o.vy
		reflected := false
		if o.position.x < sim.area.xMin+radius || o.position.x > sim.area.xMax-radius {
			o.position.x = math.Max(sim.area.xMin+radius, math.Min(o.position.x, sim.area.xMax-radius))
			o.vx = -o.vx
			reflected = true
		}
		if o.position.y < sim.area.yMin+radius || o.position.y > sim.area.yMax-radius {
			o.position.y = math.Max(sim.area.yMin+radius, math.Min(o.position.y, sim.area.yMax-radius))
			o.vy = -o.vy
			reflected = true
		}
		if reflected {
			add(2, []int64{o.id}, o.position)
		}
	}
	for i := range sim.objects {
		for j := i + 1; j < len(sim.objects); j++ {
			a, b := &sim.objects[i], &sim.objects[j]
			// Direction only covers XY. Objects collide only within the same Z plane.
			if math.Abs(a.position.z-b.position.z) > 1e-9 {
				continue
			}
			dx, dy := b.position.x-a.position.x, b.position.y-a.position.y
			distance := math.Hypot(dx, dy)
			if distance > 2*radius+1e-9 {
				continue
			}
			contactDistance := distance
			if distance < 1e-9 {
				dx, dy = previous[j].x-previous[i].x, previous[j].y-previous[i].y
				distance = math.Hypot(dx, dy)
				if distance < 1e-9 {
					continue
				}
			}
			nx, ny := dx/distance, dy/distance
			approach := (a.vx-b.vx)*nx + (a.vy-b.vy)*ny
			if approach <= 1e-9 {
				continue
			}
			point := position{(a.position.x + b.position.x) / 2, (a.position.y + b.position.y) / 2, (a.position.z + b.position.z) / 2}
			// Equal-mass elastic impulse along the contact normal.
			a.vx -= approach * nx
			a.vy -= approach * ny
			b.vx += approach * nx
			b.vy += approach * ny
			if contactDistance < 2*radius {
				a.position.x = point.x - radius*nx
				a.position.y = point.y - radius*ny
				b.position.x = point.x + radius*nx
				b.position.y = point.y + radius*ny
			}
			add(1, []int64{a.id, b.id}, point)
		}
	}
	return events
}

func (s *server) position(p position) protoreflect.Message {
	m := s.message("Position").ProtoReflect()
	setFloat(m, "x", p.x)
	setFloat(m, "y", p.y)
	setFloat(m, "z", p.z)
	return m
}

func (s *server) logEntry(sim simulation, step int, events []event) protoreflect.Message {
	logEntry := s.message("SimLog").ProtoReflect()
	setInt(logEntry, "timestamp", int64(step)*1000)
	for _, o := range sim.objects {
		entry := s.message("ObjectLog").ProtoReflect()
		setInt(entry, "object_id", o.id)
		setMessage(entry, "position", s.position(o.position))
		setFloat(entry, "speed", math.Hypot(o.vx, o.vy))
		direction := math.Atan2(o.vy, o.vx) * 180 / math.Pi
		if direction < 0 {
			direction += 360
		}
		setFloat(entry, "direction", direction)
		appendMessage(logEntry, "object_log", entry)
	}
	for _, ev := range events {
		entry := s.message("Event").ProtoReflect()
		setInt(entry, "event_id", ev.id)
		setInt(entry, "event_type", ev.kind)
		if ev.kind == 1 {
			hit := s.message("HitEvent").ProtoReflect()
			for _, id := range ev.objects {
				hit.Mutable(field(hit, "objects")).List().Append(protoreflect.ValueOfInt64(id))
			}
			setMessage(hit, "position", s.position(ev.position))
			setMessage(entry, "hit", hit)
		} else {
			reflect := s.message("ReflectedEvent").ProtoReflect()
			setInt(reflect, "id", ev.objects[0])
			setMessage(reflect, "position", s.position(ev.position))
			setMessage(entry, "reflect", reflect)
		}
		appendMessage(logEntry, "events", entry)
	}
	return logEntry
}

func (s *server) response(jobID int64, step, steps int, hitCount int64, logs []protoreflect.Message) *dynamicpb.Message {
	res := s.message("SimResponse")
	r := res.ProtoReflect()
	setInt(r, "job_id", jobID)
	progress := 1 - math.Exp(-float64(step)/5) // Estimate at the last log in the batch.
	if step == steps {
		progress = 1
	}
	setFloat(r, "progress", progress)
	for _, logEntry := range logs {
		appendMessage(r, "logs", logEntry)
	}
	if step == steps {
		result := s.message("SimResult").ProtoReflect()
		setInt(result, "exit_code", 0)
		setInt(result, "hit_count", hitCount)
		setMessage(r, "result", result)
	}
	return res
}
