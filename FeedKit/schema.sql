
-- FeedKit database schema

BEGIN IMMEDIATE TRANSACTION;

PRAGMA foreign_keys = ON;

CREATE TABLE IF NOT EXISTS info(
  ver TEXT,
  ts DATETIME DEFAULT CURRENT_TIMESTAMP
);
INSERT INTO info(ver) VALUES("1.0.0");

-- Search suggestions

CREATE TABLE IF NOT EXISTS sug(
  term TEXT UNIQUE NOT NULL COLLATE NOCASE,
  ts DATETIME DEFAULT CURRENT_TIMESTAMP
);

CREATE VIRTUAL TABLE IF NOT EXISTS sug_fts USING fts4(
  content="sug",
  term,
  ts
);

CREATE TRIGGER sug_bu BEFORE UPDATE ON sug BEGIN
  DELETE FROM sug_fts WHERE docid=old.rowid;
END;

CREATE TRIGGER sug_bd BEFORE DELETE ON sug BEGIN
  DELETE FROM sug_fts WHERE docid=old.rowid;
END;

CREATE TRIGGER sug_au AFTER UPDATE ON sug BEGIN
  INSERT INTO sug_fts(docid, term, ts) VALUES(
    new.rowid, new.term, new.ts
  );
END;

CREATE TRIGGER sug_ai AFTER INSERT ON sug BEGIN
  INSERT INTO sug_fts(docid, term, ts) VALUES(
    new.rowid, new.term, new.ts
  );
END;

-- Search

CREATE TABLE IF NOT EXISTS search_result(
  author TEXT NOT NULL,
  feed TEXT NOT NULL,
  guid INT PRIMARY KEY,
  title TEXT NOT NULL,
  ts DATETIME DEFAULT CURRENT_TIMESTAMP,
  UNIQUE(guid)
);

CREATE TABLE IF NOT EXISTS search(
  guid INT PRIMARY KEY REFERENCES search_result(guid) ON DELETE CASCADE,
  term TEXT NOT NULL COLLATE NOCASE,
  ts DATETIME DEFAULT CURRENT_TIMESTAMP,
  UNIQUE(guid, term)
);

-- Search Result FTS

CREATE VIRTUAL TABLE IF NOT EXISTS search_result_fts USING fts4(
  content="search_result",
  guid,
  author,
  title,
  ts
);

CREATE TRIGGER search_result_bu BEFORE UPDATE ON search_result BEGIN
  DELETE FROM search_result_fts WHERE docid=old.rowid;
END;

CREATE TRIGGER search_result_bd BEFORE DELETE ON search_result BEGIN
  DELETE FROM search_result_fts WHERE docid=old.rowid;
END;

CREATE TRIGGER search_result_au AFTER UPDATE ON search_result BEGIN
  INSERT INTO search_result_fts(docid, author, title, ts) VALUES(
    new.rowid, new.author, new.title, new.ts);
END;

CREATE TRIGGER search_result_ai AFTER INSERT ON search_result BEGIN
  INSERT INTO search_result_fts(docid, author, title, ts) VALUES(
    new.rowid, new.author, new.title, new.ts);
END;

-- Search FTS

CREATE VIRTUAL TABLE IF NOT EXISTS search_fts USING fts4(
  content="search",
  guid,
  term,
  ts
);

CREATE TRIGGER search_bu BEFORE UPDATE ON search BEGIN
  DELETE FROM search_fts WHERE docid=old.rowid;
END;

CREATE TRIGGER search_bd BEFORE DELETE ON search BEGIN
  DELETE FROM search_fts WHERE docid=old.rowid;
END;

CREATE TRIGGER search_au AFTER UPDATE ON search BEGIN
  INSERT INTO search_fts(docid, term, ts) VALUES(
    new.rowid, new.term, new.ts);
END;

CREATE TRIGGER search_ai AFTER INSERT ON search BEGIN
  INSERT INTO search_fts(docid, term, ts) VALUES(
    new.rowid, new.term, new.ts);
END;

COMMIT TRANSACTION;
