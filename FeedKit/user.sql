--
-- user.sql
-- FeedKit
--
-- Created by Michael Nisi on 05.02.17.
-- Copyright (c) 2017 Michael Nisi. All rights reserved.
--

pragma journal_mode = WAL;
pragma user_version = 1;

begin immediate transaction;

-- Queue Core

create table if not exists queued_entry(
  guid text primary key,
  ts datetime default current_timestamp,
  url text not null,
  since datetime,
  record_name text
) without rowid;

create unique index if not exists queued_entry_idx on queued_entry(record_name);

create table if not exists record(
  record_name text primary key,
  change_tag text
) without rowid;

create trigger if not exists record_bd before delete on record begin
  delete from queued_entry where record_name=old.record_name;
end;

create trigger if not exists queued_entry_bd before delete on queued_entry begin
  delete from record where record_name=old.record_name;
end;

-- Queue View

create view if not exists queued_entry_view
as select
  r.record_name,
  r.change_tag,
  e.guid,
  e.ts,
  e.url,
  e.since
from queued_entry e left join record r on e.record_name=r.record_name;

commit transaction;
