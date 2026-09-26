// libraryd is a small gRPC server for the runnora E2E runbooks.
// It compiles proto/library.proto at startup so the server and runbooks share one contract.
package main

import (
	"context"
	"flag"
	"fmt"
	"log"
	"net"
	"os"
	"os/signal"
	"path/filepath"
	"sort"

	"github.com/bufbuild/protocompile"
	"google.golang.org/grpc"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"
	"google.golang.org/protobuf/reflect/protoreflect"
	"google.golang.org/protobuf/types/dynamicpb"
)

type book struct {
	id, title, genre string
	available        int32
}

var books = []book{
	{"B0001", "吾輩は猫である", "NOVEL", 3},
	{"B0002", "羅生門", "NOVEL", 1},
	{"B0003", "Go言語によるWebアプリ開発", "TECH", 2},
	{"B0004", "データベース入門", "TECH", 1},
}

type libraryService interface{}

type server struct {
	getRequest  protoreflect.MessageDescriptor
	getResponse protoreflect.MessageDescriptor
	listRequest protoreflect.MessageDescriptor
	bookMessage protoreflect.MessageDescriptor
}

func main() {
	addr := flag.String("addr", "127.0.0.1:19090", "gRPC listen address")
	protoPath := flag.String("proto", "proto/library.proto", "path to the shared proto file")
	flag.Parse()

	compiler := protocompile.Compiler{Resolver: &protocompile.SourceResolver{
		ImportPaths: []string{filepath.Dir(*protoPath)},
	}}
	files, err := compiler.Compile(context.Background(), filepath.Base(*protoPath))
	if err != nil {
		log.Fatalf("compile proto: %v", err)
	}
	file := files[0]
	svc := file.Services().ByName("LibraryService")
	if svc == nil {
		log.Fatal("LibraryService not found in proto")
	}
	messages := file.Messages()
	s := &server{
		getRequest:  messages.ByName("GetBookRequest"),
		getResponse: messages.ByName("GetBookResponse"),
		listRequest: messages.ByName("ListBooksRequest"),
		bookMessage: messages.ByName("Book"),
	}
	if s.getRequest == nil || s.getResponse == nil || s.listRequest == nil || s.bookMessage == nil {
		log.Fatal("required messages not found in proto")
	}

	lis, err := net.Listen("tcp", *addr)
	if err != nil {
		log.Fatalf("listen: %v", err)
	}
	g := grpc.NewServer()
	g.RegisterService(&grpc.ServiceDesc{
		ServiceName: string(svc.FullName()),
		HandlerType: (*libraryService)(nil),
		Methods: []grpc.MethodDesc{{MethodName: "GetBook", Handler: s.getBook}},
		Streams: []grpc.StreamDesc{{StreamName: "ListBooks", Handler: s.listBooks, ServerStreams: true}},
	}, s)
	go func() {
		ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt)
		defer stop()
		<-ctx.Done()
		g.GracefulStop()
	}()
	log.Printf("library gRPC server listening on %s", lis.Addr())
	if err := g.Serve(lis); err != nil {
		log.Fatalf("serve: %v", err)
	}
}

func (s *server) getBook(_ interface{}, ctx context.Context, decode func(interface{}) error, interceptor grpc.UnaryServerInterceptor) (interface{}, error) {
	req := dynamicpb.NewMessage(s.getRequest)
	if err := decode(req); err != nil {
		return nil, err
	}
	handle := func(_ context.Context, _ interface{}) (interface{}, error) {
		id := req.Get(s.getRequest.Fields().ByName("book_id")).String()
		for _, b := range books {
			if b.id == id {
				res := dynamicpb.NewMessage(s.getResponse)
				res.Set(s.getResponse.Fields().ByName("book"), protoreflect.ValueOfMessage(s.bookValue(b).ProtoReflect()))
				return res, nil
			}
		}
		return nil, status.Errorf(codes.NotFound, "book %q not found", id)
	}
	if interceptor == nil {
		return handle(ctx, req)
	}
	return interceptor(ctx, req, &grpc.UnaryServerInfo{FullMethod: "/sample.library.v1.LibraryService/GetBook"}, handle)
}

func (s *server) listBooks(_ interface{}, stream grpc.ServerStream) error {
	req := dynamicpb.NewMessage(s.listRequest)
	if err := stream.RecvMsg(req); err != nil {
		return err
	}
	genre := req.Get(s.listRequest.Fields().ByName("genre")).String()
	ordered := append([]book(nil), books...)
	sort.Slice(ordered, func(i, j int) bool { return ordered[i].id < ordered[j].id })
	for _, b := range ordered {
		if genre != "" && b.genre != genre {
			continue
		}
		if err := stream.SendMsg(s.bookValue(b)); err != nil {
			return fmt.Errorf("send book %s: %w", b.id, err)
		}
	}
	return nil
}

func (s *server) bookValue(b book) *dynamicpb.Message {
	m := dynamicpb.NewMessage(s.bookMessage)
	fields := s.bookMessage.Fields()
	m.Set(fields.ByName("book_id"), protoreflect.ValueOfString(b.id))
	m.Set(fields.ByName("title"), protoreflect.ValueOfString(b.title))
	m.Set(fields.ByName("genre"), protoreflect.ValueOfString(b.genre))
	m.Set(fields.ByName("available_copies"), protoreflect.ValueOfInt32(b.available))
	return m
}
