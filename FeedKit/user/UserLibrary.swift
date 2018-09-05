//
//  UserLibrary.swift
//  FeedKit
//
//  Created by Michael Nisi on 18.12.17.
//  Copyright © 2017 Michael Nisi. All rights reserved.
//

import Foundation
import os.log

private let log = OSLog.disabled

/// The `UserLibrary` manages the user‘s data, for example, feed subscriptions
/// and queue.
public final class UserLibrary: EntryQueueHost {
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

    synchronize()
  }

  /// Internal serial queue for synchronizing access to shared state.
  private let sQueue = DispatchQueue(
    label: "ink.codes.feedkit.user.UserLibrary-\(UUID().uuidString).serial")

  private var _subscriptions = Set<FeedURL>()

  /// The currently subscribed URLs. Reload with `synchronize()`. Fires a
  /// `.FKSubscriptionsDidChange` notification.
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

        DispatchQueue.main.async {
          NotificationCenter.default.post(
            name: .FKSubscriptionsDidChange, object: self)
        }
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

  /// GUIDs set of enqueued items.
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

        DispatchQueue.main.async {
          NotificationCenter.default.post(
            name: .FKQueueDidChange, object: self)
        }
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

  private func queueContains(_ url: FeedURL) -> Bool {
    return queue.contains { $0.feed == url }
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

    if !queueContains(feed.url) {
      // This browser operation is already executing.
      let fetchingLatest = browser.latestEntry(feed.url)

      let enqueueing = EnqueueOperation(user: self, cache: cache)
      enqueueing.enqueueCompletionBlock = { enqueued, error in
        guard error == nil else {
          return
        }

        self.commitQueue(enqueued: Set(enqueued), dequeued: Set())
      }

      enqueueing.addDependency(fetchingLatest)
      subscribing.addDependency(enqueueing)
      operationQueue.addOperation(enqueueing)
    }

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
      let oldValue = self.subscriptions

      do {
        try self.cache.remove(urls: urls)
        let subscribed = try self.cache.subscribed()
        self.subscriptions = Set(subscribed.map { $0.url })
      } catch {
        completionHandler?(error)
        return
      }

      guard dequeueing else {
        completionHandler?(nil)
        return
      }

      let unsubscribed = oldValue.subtracting(self.subscriptions)
      let children = self.queue.filter { unsubscribed.contains($0.url) }

      do {
        let dequeued = try self.dequeue(entries: children)
        os_log("dequeued: %@", log: log, type: .debug, dequeued)
        self.commitQueue(enqueued: Set(), dequeued: dequeued)
        completionHandler?(nil)
      } catch {
        completionHandler?(error)
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

  public func synchronize(completionBlock: ((Error?) -> Void)? = nil) {
    operationQueue.addOperation {
      os_log("synchronizing", log: log, type: .debug)

      do {
        let subscribed = try self.cache.subscribed()
        self.subscriptions = Set(subscribed.map { $0.url })

        let queued = try self.cache.queued()
        self.guids = Set(queued.compactMap { $0.entryLocator.guid })

        // Evaluating our state.

        let guids = self.guids
        let q = Set(self.queue.map { $0.guid })

        let er: Error? = {
          if q.count == guids.count, q.intersection(guids).count == q.count {
            return nil
          }

          os_log("queue out of sync", log: log, type: .error)

          return QueueingError.outOfSync(q.count, guids.count)
        }()

        completionBlock?(er)
      } catch {
        os_log("failed to synchronize: %@",
               log: log, type: .error, error as CVarArg)

        completionBlock?(error)
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

  /// Commits the queue, notifying observers.
  private func commitQueue(enqueued: Set<Entry>, dequeued: Set<Entry>) {
    os_log("** committing queue", log: log,  type: .debug)

    guids = Set(queue.map { $0.guid} )

    func post(_ name: Notification.Name, userInfo: [AnyHashable : Any]? = nil) {
      DispatchQueue.main.async {
        NotificationCenter.default.post(
          name: name, object: self, userInfo: userInfo)
      }
    }

    for e in enqueued {
      post(.FKQueueDidEnqueue, userInfo: UserLibrary.makeUserInfo(entry: e))
    }

    for e in dequeued {
      post(.FKQueueDidDequeue, userInfo: UserLibrary.makeUserInfo(entry: e))
    }
  }

  public func update(
    updateComplete: ((_ newData: Bool, _ error: Error?) -> Void)?) {
    os_log("updating queue", log: log,  type: .info)

    let cache = self.cache
    let operationQueue = self.operationQueue
    let browser = self.browser

    // Synchronizing first to assure we are including the latest subscriptions.

    synchronize { error in
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
      }

      // Trimming

      let trimming = TrimQueueOperation(cache: cache)

      trimming.trimQueueCompletionBlock = { newData, error in
        if let er = error {
          os_log("trim error: %{public}@", log: log, type: .error,
                 er as CVarArg)
        }

        updateComplete?(newData, error)
      }

      enqueuing.addDependency(fetching)
      trimming.addDependency(enqueuing)

      operationQueue.addOperation(preparing)
      operationQueue.addOperation(enqueuing)
      operationQueue.addOperation(trimming)
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
    os_log("fetching queue", log: log, type: .debug)

    let fetchingQueue = FetchQueueOperation(browser: browser, cache: cache, user: self)
    fetchingQueue.entriesBlock = entriesBlock

    fetchingQueue.fetchQueueCompletionBlock = { error in
      // Forced to commit again, for fetching might have changed the queue,
      // removing unavailable items. Another reason why it’s important that
      // commit guards against redundant calls.

      // We don’t details here.
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
      // Why isn’t this a fucking set?

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
