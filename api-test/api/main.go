// 図書貸出 API のサンプル実装。
//
// openapi/library-api.yaml を実装し、データは Oracle Database (LIBAPP スキーマ) に保存する。
// runnora の E2E 検証用であり、認証やページングなど本番向けの機能は持たない。
//
// 環境変数:
//
//	LIBAPI_ADDR  待ち受けアドレス (既定 127.0.0.1:18081)
//	LIBAPI_DSN   go-ora DSN (既定 oracle://libapp:libapp_pw@127.0.0.1:1522/FREEPDB1)
package main

import (
	"context"
	"crypto/sha256"
	"database/sql"
	"encoding/hex"
	"encoding/json"
	"errors"
	"io"
	"log"
	"net/http"
	"os"
	"os/signal"
	"regexp"
	"strconv"
	"strings"
	"time"

	_ "github.com/sijms/go-ora/v2"
)

const dateLayout = "2006-01-02"

var (
	bookIDPattern = regexp.MustCompile(`^B[0-9]{4}$`)
	isbnPattern   = regexp.MustCompile(`^[0-9]{13}$`)
	genres        = map[string]bool{"NOVEL": true, "TECH": true, "HISTORY": true, "TEST": true}
)

type server struct {
	db *sql.DB
}

type apiError struct {
	Code    string `json:"code"`
	Message string `json:"message"`
}

type book struct {
	BookID          string `json:"bookId"`
	ISBN            string `json:"isbn"`
	Title           string `json:"title"`
	Author          string `json:"author"`
	Genre           string `json:"genre"`
	TotalCopies     int    `json:"totalCopies"`
	AvailableCopies int    `json:"availableCopies"`
}

type member struct {
	MemberID        string `json:"memberId"`
	Name            string `json:"name"`
	Status          string `json:"status"`
	MaxLoans        int    `json:"maxLoans"`
	ActiveLoanCount int    `json:"activeLoanCount"`
	Overdue         bool   `json:"overdue"`
}

type loan struct {
	LoanID     int64   `json:"loanId"`
	MemberID   string  `json:"memberId"`
	BookID     string  `json:"bookId"`
	LoanedAt   string  `json:"loanedAt"`
	DueDate    string  `json:"dueDate"`
	ReturnedAt *string `json:"returnedAt"`
	Status     string  `json:"status"`
}

func main() {
	addr := getenv("LIBAPI_ADDR", "127.0.0.1:18081")
	dsn := getenv("LIBAPI_DSN", "oracle://libapp:libapp_pw@127.0.0.1:1522/FREEPDB1")

	db, err := sql.Open("oracle", dsn)
	if err != nil {
		log.Fatal(err)
	}
	defer db.Close()
	db.SetMaxOpenConns(10)
	db.SetConnMaxLifetime(5 * time.Minute)

	s := &server{db: db}
	mux := http.NewServeMux()
	mux.HandleFunc("GET /health", s.getHealth)
	mux.HandleFunc("GET /books", s.listBooks)
	mux.HandleFunc("POST /books", s.createBook)
	mux.HandleFunc("GET /books/{bookId}", s.getBook)
	mux.HandleFunc("POST /books/{bookId}/cover", s.uploadBookCover)
	mux.HandleFunc("GET /members/{memberId}", s.getMember)
	mux.HandleFunc("GET /members/{memberId}/loans", s.listMemberLoans)
	mux.HandleFunc("POST /loans", s.createLoan)
	mux.HandleFunc("POST /loans/{loanId}/return", s.returnLoan)

	srv := &http.Server{Addr: addr, Handler: logRequests(mux), ReadHeaderTimeout: 5 * time.Second}
	go func() {
		stop := make(chan os.Signal, 1)
		signal.Notify(stop, os.Interrupt)
		<-stop
		ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		defer cancel()
		srv.Shutdown(ctx) //nolint:errcheck
	}()
	log.Printf("library api listening on http://%s", addr)
	if err := srv.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
		log.Fatal(err)
	}
}

// ---------------------------------------------------------------- handlers

func (s *server) getHealth(w http.ResponseWriter, r *http.Request) {
	dbStatus := "UP"
	ctx, cancel := context.WithTimeout(r.Context(), 3*time.Second)
	defer cancel()
	// DB 再作成などで切断された接続がプールに残っている場合に備えて 1 回だけ再試行する
	err := s.db.PingContext(ctx)
	if err != nil {
		err = s.db.PingContext(ctx)
	}
	if err != nil {
		log.Printf("health: %v", err)
		dbStatus = "DOWN"
	}
	writeJSON(w, http.StatusOK, map[string]string{"status": "UP", "database": dbStatus})
}

func (s *server) listBooks(w http.ResponseWriter, r *http.Request) {
	q := `SELECT book_id, isbn, title, author, genre, total_copies, available_copies FROM books WHERE 1 = 1`
	var args []any
	if g := r.URL.Query().Get("genre"); g != "" {
		if !genres[g] {
			writeError(w, http.StatusBadRequest, "VALIDATION_ERROR", "genre is invalid")
			return
		}
		args = append(args, g)
		q += ` AND genre = :` + strconv.Itoa(len(args))
	}
	if v := r.URL.Query().Get("availableOnly"); v != "" {
		only, err := strconv.ParseBool(v)
		if err != nil {
			writeError(w, http.StatusBadRequest, "VALIDATION_ERROR", "availableOnly must be boolean")
			return
		}
		if only {
			q += ` AND available_copies > 0`
		}
	}
	rows, err := s.db.QueryContext(r.Context(), q+` ORDER BY book_id`, args...)
	if err != nil {
		internalError(w, err)
		return
	}
	defer rows.Close()
	items := []book{}
	for rows.Next() {
		var b book
		if err := rows.Scan(&b.BookID, &b.ISBN, &b.Title, &b.Author, &b.Genre, &b.TotalCopies, &b.AvailableCopies); err != nil {
			internalError(w, err)
			return
		}
		items = append(items, b)
	}
	if err := rows.Err(); err != nil {
		internalError(w, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"total": len(items), "items": items})
}

func (s *server) getBook(w http.ResponseWriter, r *http.Request) {
	b, err := s.findBook(r.Context(), r.PathValue("bookId"))
	if errors.Is(err, sql.ErrNoRows) {
		writeError(w, http.StatusNotFound, "NOT_FOUND", "book not found")
		return
	}
	if err != nil {
		internalError(w, err)
		return
	}
	writeJSON(w, http.StatusOK, b)
}

func (s *server) createBook(w http.ResponseWriter, r *http.Request) {
	var in struct {
		BookID      string `json:"bookId"`
		ISBN        string `json:"isbn"`
		Title       string `json:"title"`
		Author      string `json:"author"`
		Genre       string `json:"genre"`
		TotalCopies int    `json:"totalCopies"`
	}
	if !decodeBody(w, r, &in) {
		return
	}
	var msg string
	switch {
	case !bookIDPattern.MatchString(in.BookID):
		msg = "bookId must match ^B[0-9]{4}$"
	case !isbnPattern.MatchString(in.ISBN):
		msg = "isbn must be 13 digits"
	case strings.TrimSpace(in.Title) == "" || len(in.Title) > 200:
		msg = "title is required"
	case strings.TrimSpace(in.Author) == "" || len(in.Author) > 100:
		msg = "author is required"
	case !genres[in.Genre]:
		msg = "genre is invalid"
	case in.TotalCopies < 1 || in.TotalCopies > 99:
		msg = "totalCopies must be between 1 and 99"
	}
	if msg != "" {
		writeError(w, http.StatusBadRequest, "VALIDATION_ERROR", msg)
		return
	}
	_, err := s.db.ExecContext(r.Context(),
		`INSERT INTO books (book_id, isbn, title, author, genre, total_copies, available_copies)
		 VALUES (:1, :2, :3, :4, :5, :6, :7)`,
		in.BookID, in.ISBN, in.Title, in.Author, in.Genre, in.TotalCopies, in.TotalCopies)
	if err != nil {
		if strings.Contains(err.Error(), "ORA-00001") {
			writeError(w, http.StatusConflict, "DUPLICATE_BOOK", "book already exists")
			return
		}
		internalError(w, err)
		return
	}
	b, err := s.findBook(r.Context(), in.BookID)
	if err != nil {
		internalError(w, err)
		return
	}
	writeJSON(w, http.StatusCreated, b)
}

const maxCoverSize = 1 << 20

// uploadBookCover は multipart/form-data の表紙画像を受け取り、受け取った内容の要約を返す (画像は保存しない)。
func (s *server) uploadBookCover(w http.ResponseWriter, r *http.Request) {
	r.Body = http.MaxBytesReader(w, r.Body, maxCoverSize+64*1024)
	if err := r.ParseMultipartForm(maxCoverSize + 64*1024); err != nil {
		writeError(w, http.StatusBadRequest, "VALIDATION_ERROR", "request body must be multipart/form-data")
		return
	}
	file, header, err := r.FormFile("image")
	if err != nil {
		writeError(w, http.StatusBadRequest, "VALIDATION_ERROR", "image is required")
		return
	}
	defer file.Close()
	data, err := io.ReadAll(io.LimitReader(file, maxCoverSize+1))
	if err != nil {
		internalError(w, err)
		return
	}
	// 種類は part の Content-Type ではなく中身で判定する
	contentType := http.DetectContentType(data)
	var msg string
	switch {
	case len(data) == 0:
		msg = "image is empty"
	case len(data) > maxCoverSize:
		msg = "image must be 1 MiB or less"
	case contentType != "image/png" && contentType != "image/jpeg":
		msg = "image must be PNG or JPEG"
	}
	caption := r.FormValue("caption")
	if msg == "" && len([]rune(caption)) > 100 {
		msg = "caption must be 100 characters or less"
	}
	primary := false
	if v := r.FormValue("primary"); msg == "" && v != "" {
		if primary, err = strconv.ParseBool(v); err != nil {
			msg = "primary must be boolean"
		}
	}
	if msg != "" {
		writeError(w, http.StatusBadRequest, "VALIDATION_ERROR", msg)
		return
	}

	b, err := s.findBook(r.Context(), r.PathValue("bookId"))
	if errors.Is(err, sql.ErrNoRows) {
		writeError(w, http.StatusNotFound, "NOT_FOUND", "book not found")
		return
	}
	if err != nil {
		internalError(w, err)
		return
	}
	sum := sha256.Sum256(data)
	writeJSON(w, http.StatusCreated, map[string]any{
		"bookId":      b.BookID,
		"fileName":    header.Filename,
		"contentType": contentType,
		"size":        len(data),
		"sha256":      hex.EncodeToString(sum[:]),
		"caption":     caption,
		"primary":     primary,
	})
}

func (s *server) getMember(w http.ResponseWriter, r *http.Request) {
	var m member
	var overdue int
	err := s.db.QueryRowContext(r.Context(), `
		SELECT m.member_id, m.name, m.status, m.max_loans,
		       COUNT(l.loan_id),
		       COUNT(CASE WHEN l.due_date < TRUNC(SYSDATE) THEN 1 END)
		  FROM members m
		  LEFT JOIN loans l ON l.member_id = m.member_id AND l.status = 'ACTIVE'
		 WHERE m.member_id = :1
		 GROUP BY m.member_id, m.name, m.status, m.max_loans`, r.PathValue("memberId")).
		Scan(&m.MemberID, &m.Name, &m.Status, &m.MaxLoans, &m.ActiveLoanCount, &overdue)
	if errors.Is(err, sql.ErrNoRows) {
		writeError(w, http.StatusNotFound, "NOT_FOUND", "member not found")
		return
	}
	if err != nil {
		internalError(w, err)
		return
	}
	m.Overdue = overdue > 0
	writeJSON(w, http.StatusOK, m)
}

func (s *server) listMemberLoans(w http.ResponseWriter, r *http.Request) {
	memberID := r.PathValue("memberId")
	status := r.URL.Query().Get("status")
	if status != "" && status != "ACTIVE" && status != "RETURNED" {
		writeError(w, http.StatusBadRequest, "VALIDATION_ERROR", "status is invalid")
		return
	}
	var exists int
	if err := s.db.QueryRowContext(r.Context(), `SELECT COUNT(*) FROM members WHERE member_id = :1`, memberID).Scan(&exists); err != nil {
		internalError(w, err)
		return
	}
	if exists == 0 {
		writeError(w, http.StatusNotFound, "NOT_FOUND", "member not found")
		return
	}
	q := loanSelect + ` WHERE member_id = :1`
	args := []any{memberID}
	if status != "" {
		q += ` AND status = :2`
		args = append(args, status)
	}
	rows, err := s.db.QueryContext(r.Context(), q+` ORDER BY loan_id`, args...)
	if err != nil {
		internalError(w, err)
		return
	}
	defer rows.Close()
	items := []loan{}
	for rows.Next() {
		l, err := scanLoan(rows)
		if err != nil {
			internalError(w, err)
			return
		}
		items = append(items, l)
	}
	if err := rows.Err(); err != nil {
		internalError(w, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"total": len(items), "items": items})
}

func (s *server) createLoan(w http.ResponseWriter, r *http.Request) {
	var in struct {
		MemberID string `json:"memberId"`
		BookID   string `json:"bookId"`
	}
	if !decodeBody(w, r, &in) {
		return
	}
	if in.MemberID == "" {
		writeError(w, http.StatusBadRequest, "VALIDATION_ERROR", "memberId is required")
		return
	}
	if in.BookID == "" {
		writeError(w, http.StatusBadRequest, "VALIDATION_ERROR", "bookId is required")
		return
	}

	ctx := r.Context()
	tx, err := s.db.BeginTx(ctx, nil)
	if err != nil {
		internalError(w, err)
		return
	}
	defer tx.Rollback() //nolint:errcheck

	// 会員行をロックして、同一会員の同時貸出で上限を超えないようにする
	var memberStatus string
	var maxLoans int
	err = tx.QueryRowContext(ctx, `SELECT status, max_loans FROM members WHERE member_id = :1 FOR UPDATE`, in.MemberID).
		Scan(&memberStatus, &maxLoans)
	if errors.Is(err, sql.ErrNoRows) {
		writeError(w, http.StatusNotFound, "NOT_FOUND", "member not found")
		return
	}
	if err != nil {
		internalError(w, err)
		return
	}
	if memberStatus == "SUSPENDED" {
		writeError(w, http.StatusConflict, "MEMBER_SUSPENDED", "member is suspended")
		return
	}
	var active, overdue int
	if err := tx.QueryRowContext(ctx, `
		SELECT COUNT(*), COUNT(CASE WHEN due_date < TRUNC(SYSDATE) THEN 1 END)
		  FROM loans WHERE member_id = :1 AND status = 'ACTIVE'`, in.MemberID).Scan(&active, &overdue); err != nil {
		internalError(w, err)
		return
	}
	if overdue > 0 {
		writeError(w, http.StatusConflict, "OVERDUE_LOAN", "member has overdue loans")
		return
	}
	if active >= maxLoans {
		writeError(w, http.StatusConflict, "LOAN_LIMIT_EXCEEDED", "loan limit exceeded")
		return
	}

	var available int
	err = tx.QueryRowContext(ctx, `SELECT available_copies FROM books WHERE book_id = :1 FOR UPDATE`, in.BookID).Scan(&available)
	if errors.Is(err, sql.ErrNoRows) {
		writeError(w, http.StatusNotFound, "NOT_FOUND", "book not found")
		return
	}
	if err != nil {
		internalError(w, err)
		return
	}
	if available <= 0 {
		writeError(w, http.StatusConflict, "NO_STOCK", "no available copies")
		return
	}

	var loanID int64
	if err := tx.QueryRowContext(ctx, `SELECT loan_seq.NEXTVAL FROM dual`).Scan(&loanID); err != nil {
		internalError(w, err)
		return
	}
	if _, err := tx.ExecContext(ctx, `
		INSERT INTO loans (loan_id, member_id, book_id, loaned_at, due_date, status)
		VALUES (:1, :2, :3, TRUNC(SYSDATE), TRUNC(SYSDATE) + 14, 'ACTIVE')`, loanID, in.MemberID, in.BookID); err != nil {
		internalError(w, err)
		return
	}
	if _, err := tx.ExecContext(ctx, `UPDATE books SET available_copies = available_copies - 1 WHERE book_id = :1`, in.BookID); err != nil {
		internalError(w, err)
		return
	}
	if err := tx.Commit(); err != nil {
		internalError(w, err)
		return
	}
	l, err := s.findLoan(ctx, loanID)
	if err != nil {
		internalError(w, err)
		return
	}
	writeJSON(w, http.StatusCreated, l)
}

func (s *server) returnLoan(w http.ResponseWriter, r *http.Request) {
	loanID, err := strconv.ParseInt(r.PathValue("loanId"), 10, 64)
	if err != nil {
		writeError(w, http.StatusNotFound, "NOT_FOUND", "loan not found")
		return
	}
	ctx := r.Context()
	tx, err := s.db.BeginTx(ctx, nil)
	if err != nil {
		internalError(w, err)
		return
	}
	defer tx.Rollback() //nolint:errcheck

	var status, bookID string
	err = tx.QueryRowContext(ctx, `SELECT status, book_id FROM loans WHERE loan_id = :1 FOR UPDATE`, loanID).Scan(&status, &bookID)
	if errors.Is(err, sql.ErrNoRows) {
		writeError(w, http.StatusNotFound, "NOT_FOUND", "loan not found")
		return
	}
	if err != nil {
		internalError(w, err)
		return
	}
	if status == "RETURNED" {
		writeError(w, http.StatusConflict, "ALREADY_RETURNED", "loan already returned")
		return
	}
	if _, err := tx.ExecContext(ctx, `UPDATE loans SET status = 'RETURNED', returned_at = TRUNC(SYSDATE) WHERE loan_id = :1`, loanID); err != nil {
		internalError(w, err)
		return
	}
	if _, err := tx.ExecContext(ctx, `UPDATE books SET available_copies = available_copies + 1 WHERE book_id = :1`, bookID); err != nil {
		internalError(w, err)
		return
	}
	if err := tx.Commit(); err != nil {
		internalError(w, err)
		return
	}
	l, err := s.findLoan(ctx, loanID)
	if err != nil {
		internalError(w, err)
		return
	}
	writeJSON(w, http.StatusOK, l)
}

// ---------------------------------------------------------------- queries

const loanSelect = `SELECT loan_id, member_id, book_id, loaned_at, due_date, returned_at, status FROM loans`

type scanner interface {
	Scan(dest ...any) error
}

func scanLoan(sc scanner) (loan, error) {
	var l loan
	var loanedAt, dueDate time.Time
	var returnedAt sql.NullTime
	if err := sc.Scan(&l.LoanID, &l.MemberID, &l.BookID, &loanedAt, &dueDate, &returnedAt, &l.Status); err != nil {
		return l, err
	}
	l.LoanedAt = loanedAt.Format(dateLayout)
	l.DueDate = dueDate.Format(dateLayout)
	if returnedAt.Valid {
		v := returnedAt.Time.Format(dateLayout)
		l.ReturnedAt = &v
	}
	return l, nil
}

func (s *server) findLoan(ctx context.Context, id int64) (loan, error) {
	return scanLoan(s.db.QueryRowContext(ctx, loanSelect+` WHERE loan_id = :1`, id))
}

func (s *server) findBook(ctx context.Context, id string) (book, error) {
	var b book
	err := s.db.QueryRowContext(ctx, `
		SELECT book_id, isbn, title, author, genre, total_copies, available_copies
		  FROM books WHERE book_id = :1`, id).
		Scan(&b.BookID, &b.ISBN, &b.Title, &b.Author, &b.Genre, &b.TotalCopies, &b.AvailableCopies)
	return b, err
}

// ---------------------------------------------------------------- helpers

func decodeBody(w http.ResponseWriter, r *http.Request, v any) bool {
	dec := json.NewDecoder(http.MaxBytesReader(w, r.Body, 16*1024))
	dec.DisallowUnknownFields()
	if err := dec.Decode(v); err != nil {
		writeError(w, http.StatusBadRequest, "VALIDATION_ERROR", "request body is invalid JSON")
		return false
	}
	return true
}

func writeJSON(w http.ResponseWriter, status int, body any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	if err := json.NewEncoder(w).Encode(body); err != nil {
		log.Print(err)
	}
}

func writeError(w http.ResponseWriter, status int, code, msg string) {
	writeJSON(w, status, apiError{Code: code, Message: msg})
}

func internalError(w http.ResponseWriter, err error) {
	log.Printf("internal error: %v", err)
	writeError(w, http.StatusInternalServerError, "INTERNAL_ERROR", "internal server error")
}

type statusRecorder struct {
	http.ResponseWriter
	status int
}

func (s *statusRecorder) WriteHeader(code int) {
	s.status = code
	s.ResponseWriter.WriteHeader(code)
}

func logRequests(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		start := time.Now()
		rec := &statusRecorder{ResponseWriter: w, status: http.StatusOK}
		next.ServeHTTP(rec, r)
		log.Printf("%s %s -> %d (%s)", r.Method, r.URL.RequestURI(), rec.status, time.Since(start).Round(time.Millisecond))
	})
}

func getenv(key, def string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return def
}
