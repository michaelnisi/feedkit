
-- FeedKit database schema

BEGIN IMMEDIATE TRANSACTION;

CREATE TABLE IF NOT EXISTS info(
  ver TEXT,
  ts DATETIME DEFAULT CURRENT_TIMESTAMP
);
INSERT INTO info(ver) VALUES("1.0.0");

-- Search suggestions

CREATE TABLE IF NOT EXISTS sug(
  term TEXT UNIQUE,
  cat INT DEFAULT 0,
  ts DATETIME DEFAULT CURRENT_TIMESTAMP
);

CREATE VIRTUAL TABLE IF NOT EXISTS sug_fts USING fts4(
  content="sug",
  term,
  cat,
  ts
);

CREATE TRIGGER sug_bu BEFORE UPDATE ON sug BEGIN
  DELETE FROM sug_fts WHERE docid=old.rowid;
END;

CREATE TRIGGER sug_bd BEFORE DELETE ON sug BEGIN
  DELETE FROM sug_fts WHERE docid=old.rowid;
END;

CREATE TRIGGER sug_au AFTER UPDATE ON sug BEGIN
  INSERT INTO sug_fts(docid, term, cat, ts) VALUES(
    new.rowid, new.term, new.cat, new.ts
  );
END;

CREATE TRIGGER sug_ai AFTER INSERT ON sug BEGIN
  INSERT INTO sug_fts(docid, term, cat, ts) VALUES(
    new.rowid, new.term, new.cat, new.ts
  );
END;

COMMIT TRANSACTION;
