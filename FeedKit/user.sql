--
-- user.sql
-- FeedKit
--
-- Created by Michael Nisi on 05.02.17.
-- Copyright (c) 2017 Michael Nisi. All rights reserved.
--

pragma journal_mode = WAL;
pragma user_version = 1;

begin immediate;

-- Core

-- CloudKit records

create table if not exists record(
  record_name text primary key,
  change_tag text
) without rowid;

-- Entries

create table if not exists entry(
  guid text primary key,
  since datetime,
  url text not null
) without rowid;

-- Relations

create table if not exists previous_entry(
  guid text primary key,
  ts datetime default current_timestamp,
  record_name text
) without rowid;

create unique index if not exists previous_entry_idx on previous_entry(record_name);

create trigger if not exists previous_entry_bd before delete on previous_entry begin
  delete from record where record_name = old.record_name;
end;

create table if not exists queued_entry(
  guid text primary key,
  ts datetime default current_timestamp,
  record_name text
) without rowid;

create unique index if not exists queued_entry_idx on queued_entry(record_name);

create trigger if not exists queued_entry_bd before delete on queued_entry begin
  delete from record where record_name = old.record_name;
  insert into previous_entry(guid) values(old.guid);
end;

create trigger if not exists queued_entry_bi before insert on queued_entry begin
  delete from previous_entry where guid = new.guid;
end;

create trigger if not exists entry_bd before delete on entry begin
  delete from queued_entry where guid = old.guid;
  delete from unqueued_entry where guid = old.guid;
end;

-- TODO: Delete accumulated zombie entries

-- All queued entries, including iCloud meta-data if synced

create view if not exists queued_entry_view
as select
  e.guid,
  e.since,
  e.url,
  qe.ts,
  r.change_tag,
  r.record_name
from entry e
  join queued_entry qe on qe.guid = e.guid
  left join record r on qe.record_name = r.record_name;

-- Locally queued entries, not synced yet

create view if not exists locally_queued_entry_view as
  select * from queued_entry
  where record_name is null;

-- TODO: Add views for previous entries

commit;
