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
  guid text primary key,
  url text not null,
  since datetime
) without rowid;

commit transaction;
