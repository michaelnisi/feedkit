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
  ts datetime default current_timestamp,
  guid text not null unique,
  url text not null,
  updated datetime
);

-- Subscriptions

create table if not exists subscribed_feed(
  ts datetime default current_timestamp,
  guid int unique,
  url text not null unique
);

-- Episodes

create table if not exists played_entry(
  ts datetime default current_timestamp,
  id int primary key,
  seconds int not null
);

-- Views

create view if not exists queue_view
as select *
from queued_entry;

create view if not exists time_view
as select *
from played_entry;

commit transaction;
