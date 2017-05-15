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

-- Queue

create table if not exists queued_entry(
  guid text not null unique,
  ts datetime default current_timestamp,
  url text not null
);

-- TODO: Subscriptions

create table if not exists subscribed_feed(
  guid int not null unique,
  ts datetime default current_timestamp,
  url text not null unique
);

-- Log

create table if not exists event_type(
  name text not null unique
);

insert into event_type(name) values("1-queue");
insert into event_type(name) values("2-unqueue");
insert into event_type(name) values("3-subscribe");
insert into event_type(name) values("4-unsubscribe");
insert into event_type(name) values("sync");

create table if not exists log(
  event_type int not null,
  guid text,
  ts datetime default current_timestamp,
  url text
);

create trigger if not exists queued_entry_ai after insert on queued_entry begin
  insert into log(event_type, guid, url) values(1, new.guid, new.url);
end;

create trigger if not exists queued_entry_ad after delete on queued_entry begin
  insert into log(event_type, guid, url) values(2, old.guid, old.url);
end;

-- TODO: Add subscription triggers

commit transaction;
