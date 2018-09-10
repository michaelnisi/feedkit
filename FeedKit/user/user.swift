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

  /// Posted after an item has been dequeued from the user‘s queue with the
  /// notification containing identifying information of the item.
  public static var FKQueueDidDequeue =
    NSNotification.Name("FeedKitQueueDidDequeue")
  
}

// MARK: - Queueing

/// Cache the user`s queue locally.
public protocol QueueCaching {
  
  /// Adds `queued` items.
  func add(queued: [Queued]) throws
  
  /// Removes queued entries with `guids`.
  func removeQueued(_ guids: [EntryGUID]) throws

  /// Removes all queued entries.
  func removeQueued() throws
  
  /// Removes queued entries of `feed`.
  func removeQueued(feed url: FeedURL) throws
  
  /// Trims the queue, keeping only the latest items, and items that have been
  /// explicitly enqueued by users.
  func trim() throws
  
  /// Removes previously queued entries from the cache.
  func removePrevious() throws

  /// Removes previously queued entries matching `guids` from the cache.
  func removePrevious(matching guids: [EntryGUID]) throws
  
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

/// Enumerates errors of the `Queueing` API.
public enum QueueingError: Error {
  case outOfSync(Int, Int)
}

/// Coordinates the queue data structure, local persistence, and propagation of
/// change events regarding the user’s queue.
public protocol Queueing {

  /// Adds `entries` to the queue, belonging to `owner`.
  func enqueue(
    entries: [Entry],
    belonging owner: QueuedOwner,
    enqueueCompletionBlock: ((_ enqueued: Set<Entry>, _ error: Error?) -> Void)?)
  
  /// Adds `entries` to the queue, belonging to `.nobody`.
  func enqueue(
    entries: [Entry],
    enqueueCompletionBlock: ((_ enqueued: Set<Entry>, _ error: Error?) -> Void)?)
  
  /// Removes `entry` from the queue.
  func dequeue(
    entry: Entry,
    dequeueCompletionBlock: ((_ dequeued: Set<Entry>, _ error: Error?) -> Void)?)

  /// Removes entries of `feed` from queue.
  func dequeue(
    feed: FeedURL,
    dequeueCompletionBlock: ((_ dequeued: Set<Entry>, _ error: Error?) -> Void)?)

  /// Fetches entries in the user‘s queue, populating the `queue` object of this
  /// `UserLibrary` instance.
  ///
  /// - Parameters:
  ///   - entriesBlock: A block to accumlate received entries.
  ///   - queued: All, or some, of the currently enqueued entries.
  ///   - entriesError: An error regarding this batch of entries.
  ///   - fetchQueueCompletionBlock: The completion block:
  ///   - error: An operational error if something went wrong.
  ///
  /// - Returns: Returns an executing `Operation`.
  @discardableResult func populate(
    entriesBlock: ((_ queued: [Entry], _ entriesError: Error?) -> Void)?,
    fetchQueueCompletionBlock: ((_ error: Error?) -> Void)?
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
  var isForwardable: Bool { get }
  var isBackwardable: Bool { get }
}

// MARK: - Updating

/// Updating things users care about.
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

/// Local caching of subscriptions.
public protocol SubscriptionCaching {

  /// Adds `subscriptions`.
  func add(subscriptions: [Subscription]) throws

  /// Removes subscriptions of `urls`.
  func remove(urls: [FeedURL]) throws

  /// Returns `true` if `url` is subscribed.
  func isSubscribed(_ url: FeedURL) throws -> Bool

  /// Returns current subscriptions.
  func subscribed() throws -> [Subscription]

}

/// Manages the user’s feed subscriptions.
public protocol Subscribing: Updating {

  /// Adds `subscriptions` to the user’s library.
  ///
  /// - Parameters:
  ///   - subscriptions: The subscriptions to add without timestamps.
  ///   - completionBlock: An optional completion block:
  ///   - error: An error if something went wrong.
  @discardableResult func add(
    subscriptions: [Subscription],
    completionBlock: ((_ error: Error?) -> Void)?) -> Operation

  /// Subscribes `feed`, enqueueing its latest locally cached item.
  func subscribe(_ feed: Feed, completionHandler: ((_ error: Error?) -> Void)?)
  
  /// Unsubscribe from `urls`.
  ///
  /// - Parameters:
  ///   - urls: The URLs of feeds to unsubscribe from.
  ///   - dequeueing: Dequeues children of feeds by default.
  ///   - unsubscribeComplete: An optional completion block:
  ///   - error: An error if something went wrong.
  func unsubscribe(
    _ urls: [FeedURL],
    dequeueing: Bool,
    completionHandler: ((_ error: Error?) -> Void)?)

  /// Unsubscribes from feed at `url`, deqeueing all its children.
  func unsubscribe(_ url: FeedURL, completionHandler: ((_ error: Error?) -> Void)?)
  
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
  
  /// Reloads the in-memory sets of subscriptions and enqueued GUIDs.
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
  /// records not referenced by queued entries, previously queued entries, and
  /// subscribed feeds. These records are waiting to be deleted in iCloud.
  func zombieRecords() throws -> [(String, String)]
  
  /// Deletes zombie records, unused feeds, and unused entries.
  func deleteZombies() throws

  /// Purges zone with `name`.
  func purgeZone(named name: String) throws

}


