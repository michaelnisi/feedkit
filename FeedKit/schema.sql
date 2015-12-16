-- FeedKit database schema

begin immediate transaction;

pragma journal_mode = WAL;
pragma foreign_keys = on;
pragma user_version = 1;

-- Feeds

create table if not exists feed(
  author text not null,
  guid int,
  img text,
  img100 text,
  img30 text,
  img60 text,
  img600 text,
  link text,
  summary text,
  title text not null,
  ts datetime default current_timestamp,
  updated datetime,
  url text not null unique
);

create virtual table if not exists feed_fts using fts4(
  content="feed",
  rowid,
  author,
  summary,
  title
);

create trigger feed_bu before update on feed begin
  delete from feed_fts where docid=old.rowid;
end;

create trigger feed_bd before delete on feed begin
  delete from entry where feedid=old.rowid;
  delete from feed_fts where docid=old.rowid;
end;

create trigger feed_au after update on feed begin
  insert into feed_fts(docid, author, summary, title) values(
    new.rowid,
    new.author,
    new.summary,
    new.title
  );
end;

create trigger feed_ai after insert on feed begin
  insert into feed_fts(docid, author, summary, title) values(
    new.rowid,
    new.author,
    new.summary,
    new.title
  );
end;

create view if not exists feed_view
as select
  author,
  guid,
  img,
  img100,
  img30,
  img60,
  img600,
  link,
  rowid uid,
  summary,
  title,
  ts,
  updated,
  url
from feed;

create view if not exists url_view
as select
  f.url,
  f.rowid feedid
from feed f;

-- Entries

create table if not exists entry(
  author text,
  duration text,
  feedid int not null,
  id text not null unique,
  img text,
  length int,
  link text,
  subtitle text,
  summary text,
  title text not null,
  ts datetime default current_timestamp,
  type int,
  updated datetime,
  url text
);

create virtual table if not exists entry_fts using fts4(
  content="entry",
  rowid,
  author,
  subtitle,
  summary,
  title
);

create trigger entry_bu before update on entry begin
  delete from entry_fts where docid=old.rowid;
end;

create trigger entry_bd before delete on entry begin
  delete from entry_fts where docid=old.rowid;
end;

create trigger entry_au after update on entry begin
  insert into entry_fts(docid, author, subtitle, summary, title) values(
    new.rowid,
    new.author,
    new.subtitle,
    new.summary,
    new.title
  );
end;

create trigger entry_ai after insert on entry begin
  insert into entry_fts(docid, author, subtitle, summary, title) values(
    new.rowid,
    new.author,
    new.subtitle,
    new.summary,
    new.title
  );
end;

create view if not exists entry_view
as select
  e.author,
  e.duration,
  e.id,
  e.img,
  e.length,
  e.link,
  e.subtitle,
  e.summary,
  e.title,
  e.ts,
  e.type,
  e.rowid uid,
  e.updated,
  e.url,
  f.rowid feedid,
  f.url feed
from feed f left join entry e on f.rowid=e.feedid;

-- Searching

create table if not exists search(
  feedid references feed(uid) on delete cascade,
  term text not null collate nocase,
  ts datetime default current_timestamp
);

create virtual table if not exists search_fts using fts4(
  content="search",
  feedid,
  term
);

create trigger search_bu before update on search begin
  delete from search_fts where docid=old.rowid;
end;

create trigger search_bd before delete on search begin
  delete from search_fts where docid=old.rowid;
  delete from sug where term=old.term;
end;

create trigger search_au after update on search begin
  insert into search_fts(docid, term) values(
    new.rowid,
    new.term
  );
end;

create trigger search_ai after insert on search begin
  insert into search_fts(docid, term) values(
    new.rowid,
    new.term
  );
  insert into sug(term) values(new.term);
end;

create view if not exists search_view
as select
  f.author,
  f.guid,
  f.img,
  f.img100,
  f.img30,
  f.img60,
  f.img600,
  f.link,
  f.rowid uid,
  f.summary,
  f.title,
  s.ts,
  f.updated,
  f.url
from feed f left join search s on f.rowid=s.feedid;

-- Suggestions

create table if not exists sug(
  term text unique not null collate nocase,
  ts datetime default current_timestamp
);

create virtual table if not exists sug_fts using fts4(
  content="sug",
  term,
  ts
);

create trigger sug_bu before update on sug begin
  delete from sug_fts where docid=old.rowid;
end;

create trigger sug_bd before delete on sug begin
  delete from sug_fts where docid=old.rowid;
end;

create trigger sug_au after update on sug begin
  insert into sug_fts(docid, term, ts) values(
    new.rowid, new.term, new.ts
  );
end;

create trigger sug_ai after insert on sug begin
  insert into sug_fts(docid, term, ts) values(
    new.rowid, new.term, new.ts
  );
end;

commit transaction;
