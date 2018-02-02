//
//  UserSQL.swift
//  FeedKit
//
//  Created by Michael Nisi on 15.12.17.
//  Copyright © 2017 Michael Nisi. All rights reserved.
//

import Foundation
import Skull

// MARK: - Queueing

extension SQLFormatter {
  
  static let SQLToSelectStalePrevious =
  "SELECT * FROM stale_prev_entry_guid_view;"
  
  static let SQLToSelectAllLatest =
  "SELECT * FROM latest_entry_view;"
  
  static let SQLToSelectAllQueued =
  "SELECT * FROM queued_entry_view ORDER BY ts DESC;"
  
  static let SQLToSelectAllPrevious =
  "SELECT * FROM prev_entry_view ORDER BY ts DESC;"
  
  static let SQLToTrimQueue = """
    DELETE FROM queued_entry WHERE entry_guid IN(
      SELECT entry_guid FROM stale_queued_entry_guid_view
    );
    """

  static func SQLToDeleteFromEntry(where guids: [String]) -> String {
    return "DELETE FROM entry WHERE entry_guid IN(" + guids.map {
      "'\($0)'"
    }.joined(separator: ", ") + ");"
  }
  
  static func SQLToSelectQueued(where guid: String) -> String {
    return "SELECT * FROM queued_entry WHERE entry_guid = '\(guid)';"
  }
  
  static func SQLToUnqueue(guids: [String]) -> String {
    return "DELETE FROM queued_entry WHERE entry_guid IN(" + guids.map {
      "'\($0)'"
    }.joined(separator: ", ") + ");"
  }
  
  func SQLToQueue(entry: EntryLocator, belonging: QueuedOwner = .nobody
  ) throws -> String {
    guard let guid = entry.guid else {
      throw FeedKitError.invalidEntryLocator(reason: "missing guid")
    }
    
    let url = SQLString(from: entry.url)
    let since = SQLString(from: entry.since)
    let guidStr = SQLFormatter.SQLString(from: guid)
    
    let insertEntry = """
    INSERT OR REPLACE INTO entry(
      entry_guid, feed_url, since
    ) VALUES(
      \(guidStr), \(url), \(since)
    );
    INSERT OR REPLACE INTO queued_entry(entry_guid) VALUES(\(guidStr));
    """
    
    guard case .user = belonging else {
      return insertEntry
    }
    
    return """
    \(insertEntry)
    INSERT OR REPLACE INTO pinned_entry(entry_guid) VALUES(\(guidStr));
    """
  }
  
  func entryLocator(from row: SkullRow) -> EntryLocator {
    let url = row["feed_url"] as! String
    let since = date(from: row["since"] as? String)!
    let guid = row["entry_guid"] as? String
    return EntryLocator(url: url, since: since, guid: guid)
  }
  
  func queued(from row: SkullRow, being removed: Bool = false) -> Queued {
    let locator = entryLocator(from: row)
    let ts = date(from: row["ts"] as? String)!
    
    guard !removed else {
      return Queued.previous(locator, ts)
    }
    
    // While pinned_ts being just a marker for pinned entries in the queue. It
    // has the same value as ts.
    guard let _ = date(from: row["pinned_ts"] as? String) else {
      return Queued.temporary(locator, ts)
    }
    
    return Queued.pinned(locator, ts)
  }
  
}

// MARK: - Subscribing

extension SQLFormatter {
  
  /// Returns a tuple of SQL strings from `subscription` properties.
  func strings(from subscription: Subscription)
    -> (String, String, String, String, String) {
      let iTunesID = SQLString(from: subscription.iTunes?.iTunesID)
      let img100 = SQLString(from: subscription.iTunes?.img100)
      let img30 = SQLString(from: subscription.iTunes?.img30)
      let img60 = SQLString(from: subscription.iTunes?.img60)
      let img600 = SQLString(from: subscription.iTunes?.img600)
      return (iTunesID, img100, img30, img60, img600)
  }
  
  /// The SQL to fetch all feed subscriptions.
  static let SQLToSelectSubscriptions =
  "SELECT * from subscribed_feed_view;"
  
  /// SQL to select URLs of unrelated feeds that can safely be deleted.
  static let SQLToSelectZombieFeedURLs = "SELECT * from zombie_feed_url_view;"
  
  static func SQLToSelectSubscription(where url: FeedURL) -> String {
    return "SELECT * FROM subscribed_feed WHERE feed_url = '\(url)';"
  }
  
  /// Returns SQL to replace `subscription`.
  func SQLToReplace(subscription: Subscription) -> String {
    let url = SQLFormatter.SQLString(from: subscription.url)
    
    let (iTunesID, img100, img30, img60, img600) = strings(from: subscription)
    
    let sql = """
    INSERT OR REPLACE INTO feed(
      feed_url, itunes_guid, img100, img30, img60, img600
    ) VALUES(
      \(url), \(iTunesID), \(img100), \(img30), \(img60), \(img600)
    );
    INSERT OR REPLACE INTO subscribed_feed(feed_url) VALUES(\(url));
    """
    return sql
  }
  
  /// Returns SQL to delete subscriptions for `urls`.
  static func SQLToDelete(subscribed urls: [FeedURL]) -> String {
    return "DELETE FROM subscribed_feed WHERE feed_url IN(" +
      urls.map { "'\($0)'"}.joined(separator: ", ") +
    ");"
  }
  
  func subscription(from row: SkullRow) -> Subscription {
    let url = row["feed_url"] as! String
    let iTunes = SQLFormatter.iTunesItem(from: row)
    let ts = date(from: row["ts"] as? String)!
    return Subscription(url: url, ts: ts, iTunes: iTunes)
  }
  
}

// MARK: - Integrating iTunes Metadata

extension SQLFormatter {
  
  func SQLToUpdate(iTunes: ITunesItem, where feedURL: String) -> String {
    let itunes_guid = SQLString(from: iTunes.iTunesID)
    let img100 = SQLString(from: iTunes.img100)
    let img30 = SQLString(from: iTunes.img30)
    let img60 = SQLString(from: iTunes.img60)
    let img600 = SQLString(from: iTunes.img600)
    
    let url = SQLString(from: feedURL)
    
    return """
    UPDATE feed SET \
    itunes_guid = \(itunes_guid), \
    img100 = \(img100), \
    img30 = \(img30), \
    img60 = \(img60), \
    img600 = \(img600) \
    WHERE url = \(url);
    """
  }
  
}

// MARK: - Syncing

extension SQLFormatter {
  
  static var SQLToDeleteFromSubscribed = "DELETE FROM subscribed_feed;"
  static var SQLToDeleteFromQueuedEntry = "DELETE FROM queued_entry;"
  static var SQLToDeleteFromPrevEntry = "DELETE FROM prev_entry;"

  static var SQLToDeleteAll = """
  DELETE FROM record;
  DELETE FROM feed;
  DELETE FROM entry;"
  """
  
  static var SQLToDeleteZombies = """
  DELETE FROM record WHERE record_name IN (SELECT record_name FROM zombie_record_name_view);
  DELETE FROM feed WHERE feed_url IN(SELECT feed_url FROM zombie_feed_url_view);
  DELETE FROM entry WHERE entry_guid IN(SELECT entry_guid FROM zombie_entry_guid_view);
  """
  
  // Examplary iCloud record name: C494AD71-AB58-4A00-BFDE-2551A32BC3E4
  
  static func SQLToDeleteRecords(with names: [String]) -> String {
    return "DELETE FROM record WHERE record_name IN(" + names.map {
      "'\($0)'"
    }.joined(separator: ", ") + ");"
  }
  
  private func SQLToReplaceQueued(
    locator: EntryLocator,
    timestamp: Date,
    record: RecordMetadata,
    table: String
  ) throws -> String {
    guard let locGuid = locator.guid else {
      throw FeedKitError.invalidEntryLocator(reason: "missing guid")
    }
    let guid = SQLString(from: locGuid)
    let url = SQLString(from: locator.url)
    let since = SQLString(from: locator.since)
    
    let zoneName = SQLString(from: record.zoneName)
    let recordName = SQLString(from: record.recordName)
    let tag = SQLString(from: record.changeTag)
    
    let ts = SQLString(from: timestamp)
    
    return """
    INSERT OR REPLACE INTO record(
      record_name, zone_name, change_tag
    ) VALUES(
      \(recordName), \(zoneName), \(tag)
    );
    
    INSERT OR REPLACE INTO entry(
      entry_guid, feed_url, since
    ) VALUES(
      \(guid), \(url), \(since)
    );
    
    INSERT OR REPLACE INTO \(table)(
      entry_guid, ts, record_name
    ) VALUES(
      \(guid), \(ts), \(recordName)
    );
    """
  }
  
  func SQLToReplace(synced: Synced) throws -> String {
    switch synced {
    case .subscription(let subscription, let record):
      let url = SQLString(from: subscription.url)
      
      let (iTunesID, img100, img30, img60, img600) = strings(from: subscription)
      let ts = SQLString(from: subscription.ts)
      
      let recordName = SQLString(from: record.recordName)
      let zoneName = SQLString(from: record.zoneName)
      let tag = SQLString(from: record.changeTag)
      
      let sql = """
      INSERT OR REPLACE INTO record(
        record_name, zone_name, change_tag
      ) VALUES(
        \(recordName), \(zoneName), \(tag)
      );
      
      INSERT OR REPLACE INTO feed(
        feed_url, itunes_guid, img100, img30, img60, img600
      ) VALUES(
        \(url), \(iTunesID), \(img100), \(img30), \(img60), \(img600)
      );
      
      INSERT OR REPLACE INTO subscribed_feed(
        feed_url, record_name, ts
      ) VALUES(
        \(url), \(recordName), \(ts)
      );
      """
      return sql
    case .queued(let queued, let record):
      switch queued {
      case .pinned(let loc, let ts):
        let sql = try SQLToReplaceQueued(
          locator: loc, timestamp: ts, record: record, table: "queued_entry")
        let guidStr = SQLString(from: loc.guid!)
        return """
        \(sql)
        INSERT OR REPLACE INTO pinned_entry(entry_guid) VALUES(\(guidStr));
        """
      case .temporary(let loc, let ts):
        return try SQLToReplaceQueued(
          locator: loc, timestamp: ts, record: record, table: "queued_entry")
      case .previous(let loc, let ts):
        return try SQLToReplaceQueued(
          locator: loc, timestamp: ts, record: record, table: "previous_entry")
      }
    }
  }
  
  static let SQLToSelectLocallyQueuedEntries =
  "SELECT * FROM locally_queued_entry_view;"
  
  static let SQLToSelectAbandonedRecords =
  "SELECT * FROM zombie_record_view;"
  
  static let SQLToSelectLocallySubscribedFeeds =
  "SELECT * FROM locally_subscribed_feed_view;"
  
}
