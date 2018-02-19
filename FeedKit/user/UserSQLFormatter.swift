//
//  UserSQLFormatter.swift
//  FeedKit
//
//  Created by Michael Nisi on 06.02.18.
//  Copyright © 2018 Michael Nisi. All rights reserved.
//

import Foundation
import Skull

final class UserSQLFormatter: SQLFormatter {}

// MARK: - Queueing

extension UserSQLFormatter {
  
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
  
  static func SQLToSelectEntryGUIDFromQueued(where guid: String) -> String {
    return "SELECT entry_guid FROM queued_entry WHERE entry_guid = '\(guid)';"
  }
  
  static func SQLToSelectEntryGUIDFromPrevious(where guid: String) -> String {
    return "SELECT entry_guid FROM prev_entry WHERE entry_guid = '\(guid)';"
  }
  
  static func SQLToUnqueue(guids: [String]) -> String {
    return "DELETE FROM queued_entry WHERE entry_guid IN(" + guids.map {
      "'\($0)'"
    }.joined(separator: ", ") + ");"
  }
  
  /// Optionally, returns SQL replacing a row in the `itunes` table.
  private func SQLReplacing(iTunes: ITunesItem?) -> String? {
    guard let it = iTunes else {
      return nil
    }
    
    let url = SQLString(from: it.url)
    let iTunesID = SQLString(from: it.iTunesID)
    let img100 = SQLString(from: it.img100)
    let img30 = SQLString(from: it.img30)
    let img60 = SQLString(from: it.img60)
    let img600 = SQLString(from: it.img600)
    
    return """
    INSERT OR REPLACE INTO itunes(
      feed_url, itunes_guid, img100, img30, img60, img600
    ) VALUES(
      \(url), \(iTunesID), \(img100), \(img30), \(img60), \(img600)
    );
    """
  }
  
  /// Returns SQL tuple `(url, replacingFeed)`.
  private func SQLReplacingFeed(url: String, title: String? = nil) -> (String, String) {
    let u = SQLString(from: url)
    let t = SQLString(from: title)
    
    let sql = "INSERT OR REPLACE INTO feed(feed_url, title) VALUES(\(u), \(t));"
    
    return (u, sql)
  }
  
  /// Returns SQL tuple `(guid, replacingEntry)` including `SQLReplacingFeed`.
  private func SQLReplacing(entry locator: EntryLocator) throws -> (String, String) {
    guard let guid = locator.guid else {
      throw FeedKitError.invalidEntryLocator(reason: "missing guid")
    }

    let (url, replacingFeed) = SQLReplacingFeed(url: locator.url)
    let since = SQLString(from: locator.since)
    let guidStr = SQLFormatter.SQLString(from: guid)

    let sql = """
    \(replacingFeed)
    INSERT OR REPLACE INTO entry(
      entry_guid, feed_url, since
    ) VALUES(
      \(guidStr), \(url), \(since)
    );
    """
    
    return (guidStr, sql)
  }
  
  func SQLToReplace(queued: Queued) throws -> String {
    switch queued {
    case .pinned(let locator, _, let iTunes):
      let replacingITunes = SQLReplacing(iTunes: iTunes) ?? ""
      let (guid, replacingEntry) = try SQLReplacing(entry: locator)
      
      return """
      \(replacingEntry)
      \(replacingITunes)
      INSERT OR REPLACE INTO queued_entry(entry_guid) VALUES(\(guid));
      INSERT OR REPLACE INTO pinned_entry(entry_guid) VALUES(\(guid));
      """
    case .previous(let locator, _):
      let (guid, replacingEntry) = try SQLReplacing(entry: locator)
      
      return """
      \(replacingEntry)
      INSERT OR REPLACE INTO queued_entry(entry_guid) VALUES(\(guid));
      INSERT OR REPLACE INTO prev_entry(entry_guid) VALUES(\(guid));
      """
    case .temporary(let locator, _, let iTunes):
      let replacingITunes = SQLReplacing(iTunes: iTunes) ?? ""
      let (guid, replacingEntry) = try SQLReplacing(entry: locator)
      
      return """
      \(replacingEntry)
      \(replacingITunes)
      INSERT OR REPLACE INTO queued_entry(entry_guid) VALUES(\(guid));
      """
    }
  }
  
  func entryLocator(from row: SkullRow) -> EntryLocator {
    let url = row["feed_url"] as! String
    let since = date(from: row["since"] as? String)!
    let guid = row["entry_guid"] as? String
    return EntryLocator(url: url, since: since, guid: guid)
  }
  
  /// Returns a queued item produced from a database `row`.
  ///
  /// - Parameters:
  ///   - row: The database row providing values for the item to produce.
  ///   - removed: `true` to produce a `Queued.previous` item.
  func queued(from row: SkullRow, being removed: Bool = false) -> Queued {
    let locator = entryLocator(from: row)
    let ts = date(from: row["ts"] as? String)!
    
    guard !removed else {
      return .previous(locator, ts)
    }
    
    let iTunes = UserSQLFormatter.iTunesItem(from: row, url: locator.url)
    
    // Using pinned timestamp as a marker, its value being irrelevant.
    guard let _ = date(from: row["pinned_ts"] as? String) else {
      return .temporary(locator, ts, iTunes)
    }
    
    return .pinned(locator, ts, iTunes)
  }
  
}

// MARK: - Subscribing

extension UserSQLFormatter {
  
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
    let (url, replacingFeed) = SQLReplacingFeed(
      url: subscription.url,
      title: subscription.title
    )
    let replacingITunes = SQLReplacing(iTunes: subscription.iTunes) ?? ""
    
    return """
    \(replacingFeed)
    \(replacingITunes)
    INSERT OR REPLACE INTO subscribed_feed(feed_url) VALUES(\(url));
    """
  }
  
  /// Returns SQL to delete subscriptions for `urls`.
  static func SQLToDelete(subscribed urls: [FeedURL]) -> String {
    return "DELETE FROM subscribed_feed WHERE feed_url IN(" +
      urls.map { "'\($0)'"}.joined(separator: ", ") +
    ");"
  }
  
  func subscription(from row: SkullRow) -> Subscription {
    let url = row["feed_url"] as! String
    let iTunes = SQLFormatter.iTunesItem(from: row, url: url)
    let ts = date(from: row["ts"] as? String)!
    return Subscription(url: url, ts: ts, iTunes: iTunes)
  }
  
}

// MARK: - Syncing

extension UserSQLFormatter {
  
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
  
  private func SQLReplacing(record: RecordMetadata) -> (String, String) {
    let recordName = SQLString(from: record.recordName)
    let zoneName = SQLString(from: record.zoneName)
    let tag = SQLString(from: record.changeTag)
    
    let sql = """
    INSERT OR REPLACE INTO record(
      record_name, zone_name, change_tag
    ) VALUES(
      \(recordName), \(zoneName), \(tag)
    );
    """
    
    return (recordName, sql)
  }
  
  private func SQLReplacing(
    queued: Queued, record: RecordMetadata) throws -> String {
    let (recordName, replacingRecord) = SQLReplacing(record: record)
    
    switch queued {
    case .pinned(let loc, let timestamp, let iTunes):
      let replacingITunes = SQLReplacing(iTunes: iTunes) ?? ""
      let (guid, replacingEntry) = try SQLReplacing(entry: loc)
      let ts = SQLString(from: timestamp)
      
      return """
      \(replacingEntry)
      \(replacingITunes)
      \(replacingRecord)
      INSERT OR REPLACE INTO queued_entry(
        entry_guid, ts, record_name
      ) VALUES(
        \(guid), \(ts), \(recordName)
      );
      INSERT OR REPLACE INTO pinned_entry(entry_guid) VALUES(\(guid));
      """
    case .temporary(let loc, let timestamp, let iTunes):
      let (guid, replacingEntry) = try SQLReplacing(entry: loc)
      let ts = SQLString(from: timestamp)
      let replacingITunes = SQLReplacing(iTunes: iTunes) ?? ""
      
      return """
      \(replacingEntry)
      \(replacingITunes)
      \(replacingRecord)
      INSERT OR REPLACE INTO queued_entry(
        entry_guid, ts, record_name
      ) VALUES(
        \(guid), \(ts), \(recordName)
      );
      """
    case .previous(let loc, let timestamp):
      let (guid, replacingEntry) = try SQLReplacing(entry: loc)
      let ts = SQLString(from: timestamp)
      
      return """
      \(replacingEntry)
      \(replacingRecord)
      INSERT OR REPLACE INTO prev_entry(
        entry_guid, ts, record_name
      ) VALUES(
        \(guid), \(ts), \(recordName)
      );
      """
    }
  }
  
  func SQLToReplace(synced: Synced) throws -> String {
    switch synced {
    case .subscription(let subscription, let record):
      let (url, replacingFeed) = SQLReplacingFeed(
        url: subscription.url,
        title: subscription.title
      )
      let replacingITunes = SQLReplacing(iTunes: subscription.iTunes) ?? ""
      let (recordName, replacingRecord) = SQLReplacing(record: record)
      let ts = SQLString(from: subscription.ts)
      
      return """
      \(replacingFeed)
      \(replacingITunes)
      \(replacingRecord)
      INSERT OR REPLACE INTO subscribed_feed(
        feed_url, record_name, ts
      ) VALUES(
        \(url), \(recordName), \(ts)
      );
      """
    case .queued(let queued, let record):
      return try SQLReplacing(queued: queued, record: record)
    }
  }
  
  static let SQLToSelectLocallyQueuedEntries =
  "SELECT * FROM locally_queued_entry_view;"
  
  static let SQLSelectingLocallyDequeued =
  "SELECT * FROM locally_prev_entry_view;"
  
  static let SQLToSelectAbandonedRecords =
  "SELECT * FROM zombie_record_view;"
  
  static let SQLToSelectLocallySubscribedFeeds =
  "SELECT * FROM locally_subscribed_feed_view;"
  
}
