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

--
-- Core
--

-- Feeds own entries and can be subscribed.
create table if not exists feed(
  feed_url text primary key,
  img100 text,
  img30 text,
  img60 text,
  img600 text,
  itunes_guid int unique,
  title text
) without rowid;

-- Entries are children of feeds.
create table if not exists entry(
  entry_guid text primary key,
  feed_url text not null,
  since datetime,
  title text
) without rowid;

-- Records are items synchronized with iCloud.
create table if not exists record(
  record_name text primary key,
  zone_name text not null,
  change_tag text
) without rowid;

--
-- Subsets
--

-- Entries currently in the queue.
create table if not exists queued_entry(
  entry_guid text primary key,
  ts datetime default current_timestamp,
  record_name text unique
) without rowid;

-- Previous or dequeued entries were in the queue at some point.
create table if not exists prev_entry(
  entry_guid text primary key,
  ts datetime default current_timestamp,
  record_name text unique
) without rowid;

-- Pinned entries are a subset of queued entries. These entries have been
-- explicitly enqueued by users.
create table if not exists pinned_entry(
  entry_guid text primary key,
  ts datetime default current_timestamp,
  record_name text unique
) without rowid;

create table if not exists subscribed_feed(
  feed_url text primary key,
  record_name text unique,
  ts datetime default current_timestamp
) without rowid;

--
-- Triggers
--

create trigger if not exists record_ad after delete on record begin
  delete from pinned_entry where record_name = old.record_name;
  delete from prev_entry where record_name = old.record_name;
  delete from queued_entry where record_name = old.record_name;
  delete from subscribed_feed where record_name = old.record_name;
end;

create trigger if not exists entry_ad after delete on entry begin
  delete from pinned_entry where entry_guid = old.entry_guid;
  delete from prev_entry where entry_guid = old.entry_guid;
  delete from queued_entry where entry_guid = old.entry_guid;
end;

create trigger if not exists queued_entry_ai after insert on queued_entry begin
  delete from prev_entry where entry_guid = new.entry_guid;
end;

create trigger if not exists queued_entry_ad after delete on queued_entry begin
  insert into prev_entry(entry_guid) values(old.entry_guid);
end;

create trigger if not exists feed_ad after delete on feed begin
  delete from subscribed_feed where feed_url = old.feed_url;
end;

--
-- Views
--

-- The latest, most recently updated in their respective feeds, entries,
-- queued and dequeued, per feed.
create view if not exists latest_entry_view as
select *, max(since) from entry group by feed_url;

-- All queued entries, including pinned entries, and iCloud meta-data if
-- synced. Pinned entries are signed with a pinned_ts timestamp.
create view if not exists queued_entry_view as
select
  e.entry_guid,
  e.feed_url,
  e.since,
  e.title,
  pe.ts pinned_ts,
  qe.ts,
  r.change_tag,
  r.record_name
from entry e
  join queued_entry qe on qe.entry_guid = e.entry_guid
  left join pinned_entry pe on pe.entry_guid = e.entry_guid
  left join record r on qe.record_name = r.record_name;

-- Latest queued entries, per feed.
create view if not exists latest_queued_entry_view as
select *, max(since) from queued_entry_view group by feed_url;

-- GUIDS of older, not the latest, and not enqueued by the user, queued entries
create view if not exists stale_queued_entry_guid_view as
select entry_guid from queued_entry
  except select entry_guid from latest_queued_entry_view
  except select entry_guid from pinned_entry;

-- Locally queued entries, not synced yet
create view if not exists locally_queued_entry_view as
select * from queued_entry_view
  where record_name is null;

-- Previously queued entries
create view if not exists prev_entry_view as
select
  e.entry_guid,
  e.feed_url,
  e.since,
  e.title,
  pe.ts,
  r.change_tag,
  r.record_name
from entry e
  join prev_entry pe on pe.entry_guid = e.entry_guid
  left join record r on pe.record_name = r.record_name;

-- Latest of previously queued entries, per feed
create view if not exists latest_prev_entry_view as
select *, max(since) from prev_entry_view group by feed_url;

-- GUIDs of older, not the latest, previously queued entries
create view if not exists stale_prev_entry_guid_view as
select entry_guid from prev_entry
  except select entry_guid from latest_prev_entry_view;

-- Previously queued entries that not have been synced yet
create view if not exists locally_prev_entry_view as
select * from prev_entry_view
  where record_name is null;

-- Unrelated zombie entries
create view if not exists zombie_entry_guid_view as
select entry_guid from entry
  except select entry_guid from queued_entry
  except select entry_guid from prev_entry;

-- Subscribed feeds
create view if not exists subscribed_feed_view as
select
  f.feed_url,
  f.img100,
  f.img30,
  f.img60,
  f.img600,
  f.itunes_guid,
  f.title,
  r.change_tag,
  r.record_name,
  sf.ts
from feed f
  join subscribed_feed sf on sf.feed_url = f.feed_url
  left join record r on sf.record_name = r.record_name;

-- Locally subscribed feeds, not synced yet
create view if not exists locally_subscribed_feed_view as
select * from subscribed_feed_view
  where record_name is null;

-- Unrelated zombie feeds
create view if not exists zombie_feed_url_view as
select feed_url from feed
  except select feed_url from subscribed_feed;

-- Unrelated zombie records
create view if not exists zombie_record_name_view as
  select record_name from record
    except select record_name from queued_entry
    except select record_name from prev_entry
    except select record_name from subscribed_feed;

create view if not exists zombie_record_view as
select r.record_name, r.zone_name from record r
  join zombie_record_name_view zrnv on r.record_name = zrnv.record_name;

commit;
