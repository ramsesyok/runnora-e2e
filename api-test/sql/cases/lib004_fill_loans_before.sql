-- =============================================================
-- cases/lib004_fill_loans_before.sql  (--before-sql : LIB-004 貸出上限)
-- M0001 に上限 (max_loans = 3) まで TECH の本を貸し出した状態を作る。
-- 貸出可能な本を book_id 順に探すので loan 1..3 = B0003, B0006, B0008 になる。
--
-- 使用構文: パラメータ付き明示カーソル (OPEN / FETCH / CLOSE)
--           %NOTFOUND / %ISOPEN / WHILE LOOP / EXIT WHEN
-- =============================================================
DECLARE
  CURSOR c_available (p_genre VARCHAR2) IS
    SELECT book_id
      FROM books
     WHERE genre = p_genre
       AND available_copies > 0
     ORDER BY book_id
       FOR UPDATE;

  v_member   CONSTANT members.member_id%TYPE := 'M0001';
  v_max      members.max_loans%TYPE;
  v_count    PLS_INTEGER := 0;
  v_book_id  books.book_id%TYPE;
BEGIN
  SELECT max_loans INTO v_max FROM members WHERE member_id = v_member;

  OPEN c_available('TECH');
  WHILE v_count < v_max LOOP
    FETCH c_available INTO v_book_id;
    EXIT WHEN c_available%NOTFOUND;   -- 貸出可能な本が尽きたら終了

    INSERT INTO loans (loan_id, member_id, book_id, loaned_at, due_date, status)
    VALUES (loan_seq.NEXTVAL, v_member, v_book_id, TRUNC(SYSDATE) - 1, TRUNC(SYSDATE) + 13, 'ACTIVE');

    UPDATE books SET available_copies = available_copies - 1
     WHERE CURRENT OF c_available;

    v_count := v_count + 1;
  END LOOP;
  IF c_available%ISOPEN THEN
    CLOSE c_available;
  END IF;

  IF v_count < v_max THEN
    RAISE_APPLICATION_ERROR(-20004, 'LIB-004: only ' || v_count || ' books could be lent');
  END IF;
  COMMIT;
END;
