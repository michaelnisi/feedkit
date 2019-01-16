//
//  UserLibrary.swift
//  FeedKit
//
//  Created by Michael Nisi on 18.12.17.
//  Copyright © 2017 Michael Nisi. All rights reserved.
//

import Foundation
import os.log

private let log = OSLog(subsystem: "ink.codes.feedkit", category: "user")

/// The `UserLibrary` manages the user‘s data, for example, feed subscriptions
/// and queue.
///
/// All actions emerge from imperative operation trees combining explicit
/// Operation classes with inline block operations.
public final class UserLibrary: EntryQueueHost {

  public weak var queueDelegate: QueueDelegate?

  public weak var libraryDelegate: LibraryDelegate?

  private let cache: UserCaching
  private let browser: Browsing
  private let operationQueue: OperationQueue

  /// Makes a fresh `UserLibrary` object.
  ///
  /// - Parameters:
  ///   - cache: The cache to store user data locallly.
  ///   - browser: The browser to access feeds and entries.
  ///   - queue: A serial operation queue to execute operations in order.
  public init(cache: UserCaching, browser: Browsing, queue: OperationQueue) {
    dispatchPrecondition(condition: .onQueue(.main))
    precondition(queue.maxConcurrentOperationCount == 1)

    self.cache = cache
    self.browser = browser
    self.operationQueue = queue
  }

  /// Internal serial queue for synchronizing access to shared state.
  private let sQueue = DispatchQueue(
    label: "ink.codes.feedkit.user.UserLibrary-\(UUID().uuidString).serial")

  private var _subscriptions = Set<FeedURL>()

  /// The currently subscribed URLs.
  private var subscriptions: Set<FeedURL> {
    get {
      return sQueue.sync {
        return _subscriptions
      }
    }
    set {
      sQueue.sync {
        guard _subscriptions != newValue else {
          return
        }

        _subscriptions = newValue

        libraryDelegate?.library(self, changed: _subscriptions)
      }
    }
  }

  private var _queue = Queue<Entry>()

  /// The actual queue of entries.
  var queue: Queue<Entry> {
    get {
      return sQueue.sync {
        return _queue
      }
    }

    set {
      sQueue.sync {
        _queue = newValue
      }
    }
  }

  private var _guids = Set<EntryGUID>()

  /// GUIDs of currently enqueued items.
  private var guids: Set<EntryGUID> {
    get {
      return sQueue.sync {
        return _guids
      }
    }

    set {
      sQueue.sync {
        guard _guids != newValue else {
          return
        }

        _guids = newValue

        queueDelegate?.queue(self, changed: _guids)
      }
    }
  }

}


// MARK: - Subscribing

extension UserLibrary: Subscribing {

  private func makeSubscribeOperation(
    subscriptions: [Subscription],
    completionBlock: ((_ error: Error?) -> Void)? = nil
  ) -> Operation {
    return BlockOperation(block: {
      guard !subscriptions.isEmpty else {
        completionBlock?(nil)
        return
      }

      do {
        try self.cache.add(subscriptions: subscriptions)
        let subscribed = try self.cache.subscribed()
        self.subscriptions = Set(subscribed.map { $0.url })
        completionBlock?(nil)
      } catch {
        completionBlock?(error)
      }
    })
  }

  @discardableResult public func add(
    subscriptions: [Subscription],
    completionBlock: ((_ error: Error?) -> Void)? = nil
  ) -> Operation {
    let op = makeSubscribeOperation(
      subscriptions: subscriptions, completionBlock: completionBlock)
    operationQueue.addOperation(op)
    return op
  }

  public func subscribe(_ feed: Feed, completionHandler: ((Error?) -> Void)?) {
    let s = Subscription(feed: feed)
    let subscribing = makeSubscribeOperation(subscriptions: [s]) { error in
      if let er = error {
        os_log("subscribing failed: %@", log: log, type: .error, er as CVarArg)
      } else {
        os_log("subscribed: %@", log: log, type: .debug, feed.title)
      }

      completionHandler?(error)
    }

    let fetchingLatest = browser.latestEntry(feed.url)

    let enqueueing = EnqueueOperation(user: self, cache: cache)
    enqueueing.owner = .subscriber

    enqueueing.enqueueCompletionBlock = { enqueued, error in
      guard error == nil else {
        return
      }

      self.commitQueue(enqueued: Set(enqueued))
    }

    enqueueing.addDependency(fetchingLatest)
    subscribing.addDependency(enqueueing)

    operationQueue.addOperation(enqueueing)
    operationQueue.addOperation(subscribing)
  }

  public func unsubscribe(
    _ urls: [FeedURL],
    dequeueing: Bool = true,
    completionHandler: ((_ error: Error?) -> Void)? = nil) {
    guard !urls.isEmpty else {
      return DispatchQueue.global().async {
        completionHandler?(nil)
      }
    }

    operationQueue.addOperation {
      var er: Error?
      let oldValue = self.subscriptions
      var newValue: Set<FeedURL>?

      defer {
        self.subscriptions = newValue ?? oldValue
        completionHandler?(er)
      }

      do {
        try self.cache.remove(urls: urls)
        let subscribed = try self.cache.subscribed()
        newValue = Set(subscribed.map { $0.url })
      } catch {
        return er = error
      }

      guard dequeueing, let nv = newValue else {
        return
      }

      let unsubscribed = oldValue.subtracting(nv)
      let children = self.queue.filter { unsubscribed.contains($0.url) }

      do {
        let dequeued = try self.dequeue(entries: children)
        os_log("dequeued: %@", log: log, type: .debug, dequeued)
        self.commitQueue(enqueued: Set(), dequeued: dequeued)
      } catch {
        return er = error
      }
    }
  }

  public func unsubscribe(
    _ url: FeedURL,
    completionHandler: ((_ error: Error?) -> Void)?) {
    self.unsubscribe([url], dequeueing: true, completionHandler: completionHandler)
  }

  @discardableResult
  public func fetchFeeds(
    feedsBlock: @escaping (_ feeds: [Feed], _ feedsError: Error?) -> Void,
    feedsCompletionBlock: @escaping (_ error: Error?) -> Void
    ) -> Operation {
    let op = FetchSubscribedFeedsOperation(browser: browser, cache: cache)
    op.feedsBlock = feedsBlock
    op.feedsCompletionBlock = feedsCompletionBlock
    operationQueue.addOperation(op)
    return op
  }

  public func has(subscription url: FeedURL) -> Bool {
    return subscriptions.contains(url)
  }

  public var hasNoSubscriptions: Bool {
    return subscriptions.isEmpty
  }

  public func synchronize(
    completionBlock: ((Set<FeedURL>?, Set<EntryGUID>?, Error?) -> Void)? = nil) {
    operationQueue.addOperation {
      os_log("synchronizing", log: log, type: .debug)

      do {
        let subscribed = try self.cache.subscribed()
        let s = Set(subscribed.map { $0.url })
        self.subscriptions = s

        let queued = try self.cache.queued()
        let guids = Set(queued.compactMap { $0.entryLocator.guid })
        self.guids = guids

        os_log("queue and subscriptions: (%{public}i, %{public}i)",
               log: log, type: .debug, guids.count, s.count)

        // Does the queue line up with our assumptions?

        let q = Set(self.queue.map { $0.guid })

        let er: Error? = {
          guard q.count == guids.count, // prechecking
            q.intersection(guids).count == q.count else {
            os_log("queue out of sync", log: log)
            return QueueingError.outOfSync(q.count, guids.count)
          }
          return nil
        }()

        completionBlock?(s, guids, er)
      } catch {
        os_log("failed to synchronize: %@",
               log: log, type: .error, error as CVarArg)

        completionBlock?(nil, nil, error)
      }
    }
  }

}

// MARK: - Queue Notifications

extension UserLibrary {

  private static func makeUserInfo(entry: Entry) -> [String: Any] {
    return [
      "entryGUID": entry.guid,
      "enclosureURL": entry.enclosure?.url as Any
    ]
  }

}

// MARK: - Updating

extension UserLibrary: Updating {

  /// Commits the queue, notifying delegates if anything changed, picking up
  /// guids from the queue.
  ///
  /// For just syncing `self.guids`, passing empty or no sets is fine.
  ///
  /// - Parameters:
  ///   - enqueued: Entries that have been added to the queue.
  ///   - dequeued: Entries that have been removed from the queue.
  private func commitQueue(
    enqueued: Set<Entry> = Set(), dequeued: Set<Entry> = Set()) {
    guids = Set(queue.map { $0.guid } )

    for e in enqueued {
      queueDelegate?.queue(self, enqueued: e.guid, enclosure: e.enclosure)
    }

    for e in dequeued {
      queueDelegate?.queue(self, dequeued: e.guid, enclosure: e.enclosure)
    }
  }

  public func update(
    updateComplete: ((_ newData: Bool, _ error: Error?) -> Void)?) {
    os_log("updating queue", log: log,  type: .info)

    let cache = self.cache
    let operationQueue = self.operationQueue
    let browser = self.browser

    // Synchronizing first, for including the latest subscriptions.

    synchronize { _, _, error in
      if error != nil {
        os_log("continuing update despite error", log: log)
      }

      let preparing = PrepareUpdateOperation(cache: cache)
      let fetching = browser.entries(satisfying: preparing)

      // Enqueueing

      let enqueuing = EnqueueOperation(user: self, cache: cache)

      enqueuing.enqueueCompletionBlock = { enqueued, error in
        if let er = error {
          os_log("enqueue warning: %{public}@", log: log, er as CVarArg)
        }

        // The dequeued, we don’t know.
        self.commitQueue(enqueued: Set(enqueued), dequeued: Set())
        updateComplete?(!enqueued.isEmpty, error)
      }

      enqueuing.addDependency(fetching)

      operationQueue.addOperation(preparing)
      operationQueue.addOperation(enqueuing)
    }
  }

}

// MARK: - Queueing

extension UserLibrary: Queueing {

  public var isForwardable: Bool {
    return queue.validIndexAfter != nil
  }

  public var isBackwardable: Bool {
    return queue.validIndexBefore != nil
  }

  @discardableResult
  public func populate(
    entriesBlock: ((_ queued: [Entry], _ entriesError: Error?) -> Void)? = nil,
    fetchQueueCompletionBlock: ((_ error: Error?) -> Void)? = nil
  ) -> Operation {
    os_log("populating queue", log: log, type: .debug)

    let fetchingQueue = FetchQueueOperation(browser: browser, cache: cache, user: self)
    fetchingQueue.entriesBlock = entriesBlock

    // Having no subscriptions might mean they haven’t been loaded yet.
    let isSynchronized = !subscriptions.isEmpty

    fetchingQueue.fetchQueueCompletionBlock = { error in
      guard isSynchronized else {
        return self.synchronize { _, _, syncError in
          fetchQueueCompletionBlock?(error ?? syncError)
        }
      }

      // Forced to commit again, for fetching might have changed the queue,
      // removing unavailable items. Another reason why it’s important that
      // commitQueue must guard against redundant calls.
      self.commitQueue(enqueued: Set(), dequeued: Set())

      fetchQueueCompletionBlock?(error)
    }

    let fetchingFeeds = FetchSubscribedFeedsOperation(browser: browser, cache: cache)

    fetchingFeeds.feedsBlock = { feeds, error in
      if let er = error {
        os_log("problems fetching subscribed feeds: %{public}@",
               log: log, type: .error, String(describing: er))
      }
    }

    fetchingFeeds.feedsCompletionBlock = { error in
      if let er = error {
        os_log("failed to integrate metadata %{public}@",
               log: log, type: .error, String(describing: er))
      }
    }

    fetchingQueue.addDependency(fetchingFeeds)

    operationQueue.addOperation(fetchingQueue)
    operationQueue.addOperation(fetchingFeeds)

    return fetchingQueue
  }

  public func enqueue(
    entries: [Entry],
    belonging owner: QueuedOwner,
    enqueueCompletionBlock: ((_ enqueued: Set<Entry>, _ error: Error?) -> Void)? = nil
  ) {
    let op = EnqueueOperation(user: self, cache: cache, entries: entries)
    op.owner = owner

    op.enqueueCompletionBlock = { enqueued, error in
      let e = Set(enqueued)
      self.commitQueue(enqueued: e, dequeued: Set())
      enqueueCompletionBlock?(e, error)
    }

    operationQueue.addOperation(op)
  }

  public func enqueue(
    entries: [Entry],
    enqueueCompletionBlock: ((_ enqueued: Set<Entry>, _ error: Error?) -> Void)? = nil) {
    enqueue(entries: entries,
            belonging: .nobody,
            enqueueCompletionBlock: enqueueCompletionBlock)
  }

  /// Dequeues `entries` and commits the changes. Trying to dequeue a single
  /// entry that’s not enqueued throws. Lots of ephemeral state to update here,
  /// after writing to the database.
  ///
  /// - Returns: The dequeued entries.
  ///
  /// - Throws: Throws if not at least one entry in `entries` was removed.
  private func dequeue(entries: [Entry]) throws -> Set<Entry> {
    os_log("dequeueing: %{public}@", log: log, type: .debug, entries)
    dispatchPrecondition(condition: .notOnQueue(.main))

    let wanted = entries.map { $0.guid }

    let oldValue = try cache.queued()
    try cache.removeQueued(wanted)
    let newValue = try cache.queued()

    let removed = Set(oldValue).subtracting(Set(newValue))

    let found = removed.compactMap {
      $0.entryLocator.guid
    }

    var result = Set<Entry>()

    for entry in entries {
      guard found.contains(entry.guid) else {
        continue
      }

      do {
        try queue.remove(entry)
        result.insert(entry)
      } catch {
        os_log("not removed: %{public}@", log: log, error as CVarArg)
        guard entries.count > 1 else {
          throw error
        }
        continue
      }
    }

    return result
  }

  public func dequeue(
    entry: Entry,
    dequeueCompletionBlock: ((_ dequeued: Set<Entry>, _ error: Error?) -> Void)?) {
    operationQueue.addOperation {
      let entries = [entry]
      do {
        let dequeued = try self.dequeue(entries: entries)
        self.commitQueue(enqueued: Set(), dequeued: dequeued)
        dequeueCompletionBlock?(dequeued, nil)
      } catch {
        dequeueCompletionBlock?([], error)
      }
    }
  }

  public func dequeue(
    feed url: FeedURL,
    dequeueCompletionBlock: ((_ dequeued: Set<Entry>, _ error: Error?) -> Void)?) {
    operationQueue.addOperation {
      let children = self.queue.filter { $0.url == url }
      do {
        let dequeued = try self.dequeue(entries: children)
        self.commitQueue(enqueued: Set(), dequeued: dequeued)
        dequeueCompletionBlock?(dequeued, nil)
      } catch {
        dequeueCompletionBlock?([], error)
      }
    }
  }

  public func contains(entry: Entry) -> Bool {
    return guids.contains(entry.guid)
  }

  public var isEmpty: Bool {
    return guids.isEmpty
  }

  public func next() -> Entry? {
    return queue.forward()
  }

  public func previous() -> Entry? {
    return queue.backward()
  }

  public func skip(to entry: Entry) throws {
    try queue.skip(to: entry)
  }

}
