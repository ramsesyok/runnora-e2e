-- =============================================================
-- common/10_seed_master.sql  (runnora.yaml の環境 unit の hooks.before 2/2)
-- 会員・蔵書のマスタデータを投入する。
-- OpenAPI の example (B0001, M0001 など) と同じ値にしてあるため、
-- 生成テスト (runnora generate) とモック (oapi2wire) の期待値が実 API でも成り立つ。
--
-- 使用構文: MERGE / レコード型 + 連想配列 (INDEX BY) / 修飾式 (18c+)
--           数値 FOR LOOP / CASE 式 / 局所ファンクション
-- =============================================================
DECLARE
  TYPE t_book IS RECORD (
    book_id books.book_id%TYPE,
    title   books.title%TYPE,
    author  books.author%TYPE,
    genre   books.genre%TYPE,
    copies  books.total_copies%TYPE
  );
  TYPE t_book_tab IS TABLE OF t_book INDEX BY PLS_INTEGER;
  v_books  t_book_tab;
  v_genre  books.genre%TYPE;
  v_copies books.total_copies%TYPE;
  v_isbn   books.isbn%TYPE;

  -- ISBN は 978400000 + 4 桁連番 (B0001 → 9784000000001)
  -- 局所ファンクションは SQL 文の中から呼べない (PLS-00231) ので、変数に代入してから使う
  FUNCTION isbn_of(p_no IN PLS_INTEGER) RETURN VARCHAR2 IS
  BEGIN
    RETURN '978400000' || TO_CHAR(p_no, 'FM0000');
  END isbn_of;
BEGIN
  -- 1) 名前付きの会員 : MERGE で「あれば更新・なければ登録」
  MERGE INTO members m
  USING (
    SELECT 'M0001' AS member_id, '山田 太郎' AS name, 'ACTIVE' AS status FROM dual UNION ALL
    SELECT 'M0002', '佐藤 花子', 'ACTIVE'    FROM dual UNION ALL
    SELECT 'M0003', '鈴木 一郎', 'SUSPENDED' FROM dual
  ) s
  ON (m.member_id = s.member_id)
  WHEN MATCHED THEN
    UPDATE SET m.name = s.name, m.status = s.status, m.max_loans = 3
  WHEN NOT MATCHED THEN
    INSERT (member_id, name, status, max_loans) VALUES (s.member_id, s.name, s.status, 3);

  -- 2) 汎用テスト会員 M0004 〜 M0010 : 数値 FOR LOOP
  FOR i IN 4 .. 10 LOOP
    INSERT INTO members (member_id, name, status, max_loans)
    VALUES ('M' || TO_CHAR(i, 'FM0000'), 'テスト会員 ' || TO_CHAR(i, 'FM00'), 'ACTIVE', 3);
  END LOOP;

  -- 3) 名前付きの蔵書 : レコードの連想配列を修飾式で組み立てて FOR LOOP で登録
  v_books(1) := t_book('B0001', '吾輩は猫である',            '夏目漱石',   'NOVEL',   3);
  v_books(2) := t_book('B0002', '羅生門',                    '芥川龍之介', 'NOVEL',   1);
  v_books(3) := t_book('B0003', 'Go言語によるWebアプリ開発', '技術 一郎',  'TECH',    2);
  v_books(4) := t_book('B0004', '日本の城郭史',              '歴史 次郎',  'HISTORY', 1);

  FOR i IN 1 .. v_books.COUNT LOOP
    v_isbn := isbn_of(i);
    INSERT INTO books (book_id, isbn, title, author, genre, total_copies, available_copies)
    VALUES (v_books(i).book_id, v_isbn, v_books(i).title, v_books(i).author,
            v_books(i).genre, v_books(i).copies, v_books(i).copies);
  END LOOP;

  -- 4) 汎用テスト図書 B0005 〜 B0020 : ジャンルと冊数を CASE 式で振り分ける
  --    (NOVEL は B0001/B0002 の 2 冊だけにして、OpenAPI example の件数と一致させる)
  FOR i IN 5 .. 20 LOOP
    v_genre  := CASE MOD(i, 2) WHEN 0 THEN 'TECH' ELSE 'HISTORY' END;
    v_copies := CASE WHEN i <= 10 THEN 1 ELSE 2 END;
    v_isbn   := isbn_of(i);
    INSERT INTO books (book_id, isbn, title, author, genre, total_copies, available_copies)
    VALUES ('B' || TO_CHAR(i, 'FM0000'), v_isbn, 'テスト図書 ' || TO_CHAR(i, 'FM00'),
            'テスト 著者', v_genre, v_copies, v_copies);
  END LOOP;

  COMMIT;
END;
