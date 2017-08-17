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
  url text not null,
  record_name text
) without rowid;

-- Feeds

create table if not exists feed(
  url text not null,
  record_name text
);

-- Relations

-- TODO: Update relations to use core tables

-- Queued entry locators

create table if not exists queued_entry(
  guid text primary key,
  since datetime,
  ts datetime default current_timestamp,
  url text not null,
  record_name text
) without rowid;

create unique index if not exists queued_entry_idx on queued_entry(record_name);

create trigger if not exists queued_entry_bd before delete on queued_entry begin
  delete from record where record_name=old.record_name;
end;

-- TODO: Refactoring starts here

create table if not exists qe(
  guid text primary key,
  ts datetime default current_timestamp
) without rowid;

create table if not exists qe(
  guid text primary key,
  ts datetime default current_timestamp
) without rowid;

create view if not exists qe_view
as select
  r.record_name,
  r.change_tag,
  e.guid,
  e.ts,
  e.url,
  e.since
from queued_entry e
  join qe on qe.guid = e.guid
  left join record r on e.record_name=r.record_name;

--

-- All entries in queue including CloudKit meta data, if synced

create view if not exists queued_entry_view
as select
  r.record_name,
  r.change_tag,
  e.guid,
  e.ts,
  e.url,
  e.since
from queued_entry e left join record r on e.record_name=r.record_name;

-- Locally queued entries, not synced yet

create view if not exists locally_queued_entry as
  select * from queued_entry
  where record_name is null;

-- TODO: Subscriptions

create table if not exists subscription(
  url text not null,
  ts datetime default current_timestamp,
  record_name text
);

create trigger if not exists subscription_bd before delete on subscription begin
  delete from record where record_name=old.record_name;
end;

create view if not exists subscription_view
as select
  r.record_name,
  r.change_tag,
  s.ts,
  s.url
from subscription s left join record r on s.record_name=r.record_name;

-- Deleting entries and subscriptions with their according records

create trigger if not exists record_bd before delete on record begin
  delete from queued_entry where record_name=old.record_name;
  delete from subscription where record_name=old.record_name;
end;

commit;
