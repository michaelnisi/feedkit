//
//  user.swift
//  FeedKit
//
//  Created by Michael Nisi on 31/01/16.
//  Copyright © 2016 Michael Nisi. All rights reserved.
//

import AVFoundation
import Foundation
import Skull
import os.log

struct User {
  static let log = OSLog(subsystem: "ink.codes.feedkit", category: "user")
  
  // I guess this extra operation queue once made sense.
  
  // TODO: Remove extra queue
  static let queue = OperationQueue()
}

// MARK: - Notifications

public extension Notification.Name {
  
  /// Posted after the users‘s subscriptions have been changed.
  public static var FKSubscriptionsDidChange =
    NSNotification.Name("FeedKitSubscriptionsDidChange")
  
  /// Posted after the user‘s queue has been changed.
  public static var FKQueueDidChange =
    NSNotification.Name("FeedKitQueueDidChange")
  
  /// Posted after a new item has been enqueued to the user‘s queue with the
  /// notification containing identifying information of the item.
  public static var FKQueueDidEnqueue =
    NSNotification.Name("FeedKitQueueDidEnqueue")
  
}

// MARK: - Queueing

/// Cache the user`s queue locally.
public protocol QueueCaching {
  
  /// Adds `queued` items.
  func add(queued: [Queued]) throws
  
  /// Removes queued entries with `guids`.
  func removeQueued(_ guids: [EntryGUID]) throws
  
  /// Trims the queue, keeping only the latest items, and items that have been
  /// explicitly enqueued by users.
  func trim() throws
  
  /// Removes all queued entries.
  func removeQueued() throws
  
  /// Removes previously queued entries from the cache.
  func removePrevious() throws
  
  /// Removes all entries, previous and currently queued, from the cache.
  func removeAll() throws
  
  /// Removes stale, all but the latest, previously queued entries.
  func removeStalePrevious() throws
  
  /// The user‘s queued entries, in descending order by time queued.
  func queued() throws -> [Queued]
  
  /// Previously queued entries, in descending order by time dequeued.
  func previous() throws -> [Queued]
  
  /// The newest entry locators—one per feed, sorted by publishing date, newest
  /// first—of current and previous entries.
  func newest() throws -> [EntryLocator]
  
  /// All previously and currently queued items in no specific order.
  func all() throws -> [Queued]
  
  /// Checks if an entry with `guid` is currently contained in the locally
  /// cached queue.
  func isQueued(_ guid: EntryGUID) throws -> Bool
  
  /// Checks if an entry with `guid` is currently contained in the local cache
  /// of previously queued entries.
  func isPrevious(_ guid: EntryGUID) throws -> Bool
  
}

/// Confines `Queue` state dependency.
protocol EntryQueueHost {
  var queue: Queue<Entry> { get set }
}

/// Enumerates possible owners of enqueued items, default is `.nobody`.
public enum QueuedOwner: Int {
  case nobody, user
}

/// Coordinates the queue data structure, local persistence, and propagation of
/// change events regarding the user’s queue.
public protocol Queueing {
  
  /// Adds `entries` to the queue.
  func enqueue(
    entries: [Entry],
    belonging: QueuedOwner,
    enqueueCompletionBlock: ((_ error: Error?) -> Void)?) throws
  
  /// Adds `entries` to the queue.
  func enqueue(
    entries: [Entry],
    enqueueCompletionBlock: ((_ error: Error?) -> Void)?) throws
  
  /// Removes `entry` from the queue.
  func dequeue(
    entry: Entry,
    dequeueCompletionBlock: ((_ error: Error?) -> Void)?)
  
  /// Fetches entries in the user‘s queue, populating the `queue` object of this
  /// `UserLibrary` instance.
  ///
  /// - Parameters:
  ///   - entriesBlock: The entries block:
  ///   - entriesError: An optional error, specific to entries.
  ///   - entries: All or some of the requested entries.
  ///
  ///   - fetchQueueCompletionBlock: The completion block:
  ///   - error: Optionally, an error for this operation.
  ///
  /// - Returns: Returns an executing `Operation`.
  @discardableResult func fetchQueue(
    entriesBlock: @escaping (_ queued: [Entry], _ entriesError: Error?) -> Void,
    fetchQueueCompletionBlock: @escaping (_ error: Error?) -> Void
  ) -> Operation
  
  // MARK: Queue
  
  // These synchronous methods are super fast (AP), but may not be consistent.
  // For example, to meaningfully use these, you must `fetchQueue` first.
  // https://en.wikipedia.org/wiki/CAP_theorem
  
  func contains(entry: Entry) -> Bool
  func next() -> Entry?
  func previous() -> Entry?
  func skip(to entry: Entry) throws
  
  var isEmpty: Bool { get }
}

// MARK: - Updating

/// Updating things users cares about.
public protocol Updating {
  
  /// Updates entries of subscribed feeds. Errors passed to the completion
  /// block may be partial and not necessarily critical.
  ///
  /// - Parameters:
  ///   - updateComplete: The completion block to apply when done.
  ///   - newData: `true` if new data has been received.
  ///   - error: Optionally, not conclusively critical, error.
  func update(updateComplete: ((_ newData: Bool, _ error: Error?) -> Void)?)
  
}

// MARK: - Subscribing

public protocol SubscriptionCaching {
  func add(subscriptions: [Subscription]) throws
  func remove(urls: [FeedURL]) throws
  
  func isSubscribed(_ url: FeedURL) throws -> Bool
  
  func subscribed() throws -> [Subscription]
}

/// Mangages the user’s feed subscriptions.
public protocol Subscribing: Updating {
  
  /// Adds `subscriptions` to the user’s library.
  ///
  /// - Parameters:
  ///   - subscriptions: The subscriptions to add without timestamps.
  ///   - addComplete: An optional completion block:
  ///   - error: An error if something went wrong.
  func add(
    subscriptions: [Subscription],
    addComplete: ((_ error: Error?) -> Void)?) throws
  
  /// Unsubscribe from `urls`.
  ///
  /// - Parameters:
  ///   - urls: The URLs of feeds to unsubscribe from.
  ///   - unsubscribeComplete: An optional completion block:
  ///   - error: An error if something went wrong.
  func unsubscribe(
    from urls: [FeedURL],
    unsubscribeComplete: ((_ error: Error?) -> Void)?) throws
  
  /// Fetches the feeds currently subscribed.
  ///
  /// - Parameters:
  ///   - feedsBlock: A block applied with the resulting feeds:
  ///   - feeds: The subscribed feeds.
  ///   - feedsError: Optionally, an error related to feed fetching.
  ///
  ///   - feedsCompletionBlock: The completion block of this operation:
  ///   - error: An error if something went wrong with this operation.
  func fetchFeeds(
    feedsBlock: @escaping (_ feeds: [Feed], _ feedsError: Error?) -> Void,
    feedsCompletionBlock: @escaping (_ error: Error?) -> Void
    ) -> Operation
  
  /// Returns `true` if `url` is subscribed. You must `fetchFeeds` first, before
  /// relying on this.
  func has(subscription url: FeedURL) -> Bool
  
  /// Reloads the in-memory cache of locally cached subscriptions and enqueued
  /// items.
  func synchronize(completionBlock: ((Error?) -> Void)?)
  
}

// MARK: - UserCaching

/// Caches user data, queue and subscriptions, locally.
public protocol UserCaching: QueueCaching, SubscriptionCaching {}

// MARK: - Syncing

/// Encapsulates `CKRecord` data to **avoid CloudKit dependency within
/// FeedKit** framework.
public struct RecordMetadata {
  let zoneName: String
  let recordName: String
  let changeTag: String?
  
  public init(zoneName: String, recordName: String, changeTag: String? = nil) {
    self.zoneName = zoneName
    self.recordName = recordName
    self.changeTag = changeTag
  }
}

extension RecordMetadata: Equatable {
  public static func ==(lhs: RecordMetadata, rhs: RecordMetadata) -> Bool {
    guard
      lhs.zoneName == rhs.zoneName,
      lhs.recordName == rhs.recordName,
      lhs.changeTag == rhs.changeTag
      else {
      return false
    }
    return true
  }
}

/// Enumerates data structures that are synchronized with iCloud.
public enum Synced {
  
  /// A queued item that has been synchronized with the iCloud database.
  case queued(Queued, RecordMetadata)
  
  /// A synchronized feed subscription.
  case subscription(Subscription, RecordMetadata)
}

extension Synced: Equatable {
  public static func ==(lhs: Synced, rhs: Synced) -> Bool {
    switch (lhs, rhs) {
    case (.queued(let lq, let lrec), .queued(let rq, let rrec)):
      return lq == rq && lrec == rrec
    case (.subscription(let ls, let lrec), .subscription(let rs, let rrec)):
      return ls == rs && lrec == rrec
    case (.queued, _), (.subscription, _):
      return false
    }
  }
}

/// Sychronizes with iCloud.
public protocol UserCacheSyncing: QueueCaching, SubscriptionCaching {
  
  /// Saves `synced`, synchronized user items, to the local cache.
  func add(synced: [Synced]) throws
  
  /// Removes records with `recordNames` from the local cache.
  func remove(recordNames: [String]) throws
  
  /// The queued entries, which have not been synced and are only locally
  /// cached, hence the name. Push these items with the next sync.
  func locallyQueued() throws -> [Queued]
  
  /// Previously queued items, which have not been synced yet.
  func locallyDequeued() throws -> [Queued]
  
  /// Returns subscriptions that haven’t been synchronized with iCloud yet, and
  /// are only cached locally so far. Push these items with the next sync.
  func locallySubscribed() throws -> [Subscription]
  
  /// CloudKit record names of abandoned records by record zone names. These are
  /// records not referenced by queued or previously queued entries, and not
  /// referenced by subscribed feeds. If this collection isn’t empty, items have
  /// been removed from the cache waiting to be synchronized. Include these in
  /// every push.
  func zombieRecords() throws -> [(String, String)]
  
  /// Deletes unrelated items from the cache. After records have been deleted in
  /// iCloud, and these have been synchronized with the local cache, entries
  /// and feeds might be left without links to their, now deleted, records. This
  /// method deletes those entries and feeds, it also deletes zombie records,
  /// not having links in the other direction. Run this after each sync.
  func deleteZombies() throws
  
  /// Deletes all queue data.
  func removeQueue() throws
  
  /// Deletes all library data.
  func removeLibrary() throws
  
  /// Deletes all log data.
  func removeLog() throws
  
}



