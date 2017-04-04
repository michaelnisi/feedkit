-- A schema for browsing and searching feeds and entries.

-- TODO: Rename this file to cache.sql

pragma journal_mode = WAL;
pragma user_version = 1;

begin immediate transaction;

-- Feeds

create table if not exists feed(
  author text,
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

create trigger if not exists feed_ts after update on feed for each row begin
  update feed set ts = current_timestamp where rowid = old.rowid;
end;

create virtual table if not exists feed_fts using fts4(
  content="feed",
  rowid,
  author,
  summary,
  title
);

create trigger if not exists feed_bu before update on feed begin
  delete from feed_fts where docid=old.rowid;
end;

create trigger if not exists feed_bd before delete on feed begin
  delete from entry where feedid=old.rowid;
  delete from feed_fts where docid=old.rowid;
  delete from search where feedid=old.rowid;
end;

create trigger if not exists feed_au after update on feed begin
  insert into feed_fts(docid, author, summary, title) values(
    new.rowid,
    new.author,
    new.summary,
    new.title
  );
end;

create trigger if not exists feed_ai after insert on feed begin
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

-- TODO: Review url_view view

create view if not exists url_view
as select
  f.url,
  f.rowid feedid
from feed f;

-- Entries

create table if not exists entry(
  author text,
  duration int,
  feedid int not null,
  guid text not null unique,
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

create unique index if not exists entry_guid_idx on entry(guid);

create virtual table if not exists entry_fts using fts4(
  content="entry",
  rowid,
  author,
  subtitle,
  summary,
  title
);

create trigger if not exists entry_bu before update on entry begin
  delete from entry_fts where docid=old.rowid;
end;

create trigger if not exists entry_bd before delete on entry begin
  delete from entry_fts where docid=old.rowid;
end;

create trigger if not exists entry_au after update on entry begin
  insert into entry_fts(docid, author, subtitle, summary, title) values(
    new.rowid,
    new.author,
    new.subtitle,
    new.summary,
    new.title
  );
end;

create trigger if not exists entry_ai after insert on entry begin
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
  e.guid,
  e.img,
  e.length,
  e.link,
  e.rowid uid,
  e.subtitle,
  e.summary,
  e.title,
  e.ts,
  e.type,
  e.updated,
  e.url,
  f.img feed_image,
  f.img100,
  f.img30,
  f.img60,
  f.img600,
  f.rowid feedid,
  f.title feed_title,
  f.url feed
from feed f inner join entry e on f.rowid=e.feedid;

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

create trigger if not exists sug_bu before update on sug begin
  delete from sug_fts where docid=old.rowid;
end;

create trigger if not exists sug_bd before delete on sug begin
  delete from sug_fts where docid=old.rowid;
end;

create trigger if not exists sug_au after update on sug begin
  insert into sug_fts(docid, term, ts) values(
    new.rowid, new.term, new.ts
  );
end;

create trigger if not exists sug_ai after insert on sug begin
  insert into sug_fts(docid, term, ts) values(
    new.rowid, new.term, new.ts
  );
end;

-- Searching

create table if not exists search(
  feedid int not null,
  term text not null collate nocase,
  ts datetime default current_timestamp
);

create virtual table if not exists search_fts using fts4(
  content="search",
  feedid,
  term
);

create trigger if not exists search_bu before update on search begin
  delete from search_fts where docid=old.rowid;
end;

create trigger if not exists search_bd before delete on search begin
  delete from search_fts where docid=old.rowid;
  delete from sug where term=old.term;
end;

create trigger if not exists search_au after update on search begin
  insert into search_fts(docid, term) values(
    new.rowid,
    new.term
  );
end;

create trigger if not exists search_ai after insert on search begin
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

commit transaction;
