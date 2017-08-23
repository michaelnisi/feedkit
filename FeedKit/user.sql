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

-- CloudKit synchronization log

create table if not exists server(
  database_change_token blob,
  previous_change_token blob,
  queue_change_token blob,
  subscriptions_change_token blob,
  ts datetime default current_timestamp
);

-- CloudKit records

create table if not exists record(
  record_name text primary key,
  change_tag text
) without rowid;

-- Entries

-- TODO: Once guid is changed to int, use ordinary rowid

create table if not exists entry(
  guid text primary key,
  since datetime,
  url text not null
) without rowid;

-- Queued entries

create table if not exists queued_entry(
  guid text primary key,
  ts datetime default current_timestamp,
  record_name text unique
) without rowid;

create unique index if not exists queued_entry_idx on queued_entry(record_name);

-- Previously queued entries

create table if not exists previous_entry(
  guid text primary key,
  ts datetime default current_timestamp,
  record_name text unique
) without rowid;

create unique index if not exists previous_entry_idx on previous_entry(record_name);

-- Feeds

create table if not exists feed(
  guid int primary key,
  url text not null
);

-- Subscribed feeds

create table if not exists subscribed_feed(
  guid int primary key,
  ts datetime default current_timestamp,
  record_name text unique
);

create unique index if not exists subscribed_feed_idx on subscribed_feed(record_name);

-- Relations

create trigger if not exists record_ad after delete on record begin
  delete from queued_entry where record_name = old.record_name;
  delete from previous_entry where record_name = old.record_name;
  delete from subscribed_feed where record_name = old.record_name;
end;

create trigger if not exists queued_entry_ad after delete on queued_entry begin
  insert into previous_entry(guid) values(old.guid);
end;

create trigger if not exists queued_entry_ai after insert on queued_entry begin
  delete from previous_entry where guid = new.guid;
end;

create trigger if not exists entry_ad after delete on entry begin
  delete from queued_entry where guid = old.guid;
  delete from previous_entry where guid = old.guid;
end;

create trigger if not exists feed_ad after delete on feed begin
  delete from subscribed_feed where guid = old.guid;
end;

-- All queued entries, including iCloud meta-data if synced

create view if not exists queued_entry_view as
select
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
select * from queued_entry_view
  where record_name is null;

-- Previously queued entries

create view if not exists previous_entry_view as
select
  e.guid,
  e.since,
  e.url,
  pe.ts,
  r.change_tag,
  r.record_name
from entry e
  join previous_entry pe on pe.guid = e.guid
  left join record r on pe.record_name = r.record_name;

-- Previously queued entries that not have been synced yet

create view if not exists locally_previous_entry_view as
select * from previous_entry_view
  where record_name is null;

-- Unrelated zombie entries

create view if not exists zombie_entry_guid_view as
select guid from entry
  where guid not in (select guid from queued_entry) and (select guid from previous_entry);

-- Subscribed feeds

create view if not exists subscribed_feed_view as
select
  f.guid,
  f.url,
  sf.ts,
  r.change_tag,
  r.record_name
from feed f
  join subscribed_feed sf on sf.guid = f.guid
  left join record r on sf.record_name = r.record_name;

-- Locally subscribed feeds, not synced yet

create view if not exists locally_subscribed_feed_view as
select * from subscribed_feed_view
  where record_name is null;

-- Unrelated zombie feeds

create view if not exists zombie_feed_guid_view as
select guid from feed
  where guid not in (select guid from subscribed_feed);

commit;
