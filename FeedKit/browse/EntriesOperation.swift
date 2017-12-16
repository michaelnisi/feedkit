//
//  EntriesOperation.swift
//  FeedKit
//
//  Created by Michael Nisi on 15.12.17.
//  Copyright © 2017 Michael Nisi. All rights reserved.
//

import Foundation
import MangerKit
import Ola
import os.log

protocol ProvidingReachability{
  var error: Error? { get }
  var status: OlaStatus { get }
}

protocol ProvidingLocators {
  var error: Error? { get }
  var locators: [EntryLocator]  { get }
}

protocol ProvidingEntries {
  var error: Error? { get }
  var entries: [Entry] { get }
}

// MARK: - Entries

/// Comply with MangerKit API to enable using the remote service.
extension EntryLocator: MangerQuery {}

final class EntriesOperation: BrowseOperation, ProvidingEntries {

  // MARK: Providing Entries

  private(set) var error: Error?
  private(set) var entries = [Entry]()

  // MARK: Callbacks

  var entriesBlock: ((Error?, [Entry]) -> Void)?
  var entriesCompletionBlock: ((Error?) -> Void)?

  // MARK: State

  var _locators: [EntryLocator]?

  lazy var locators: [EntryLocator] = {
    guard let locs = _locators else {

      var reqError: Error?

      let found = dependencies.reduce([EntryLocator]()) { acc, dep in
        if case let req as ProvidingLocators = dep {
          guard req.error == nil else {
            reqError = req.error
            return acc
          }
          return acc + req.locators
        }
        return acc
      }

      guard reqError == nil, !found.isEmpty else {
        done(reqError)
        return []
      }

      _locators = found
      return found
    }

    return locs
  }()

  // Identifiers of entries that already have been dispatched.
  var dispatched = [String]() {
    didSet {
      os_log("dispatched: %@", log: BrowseLog.log, type: .debug, dispatched)
    }
  }

  /// Creates an entries operation with the specified cache, service, dispatch
  /// queue, and entry locators.
  ///
  /// Refer to `BrowseOperation` for more information.
  ///
  /// - Parameter locators: The selection of entries to fetch.
  init(cache: FeedCaching, svc: MangerService, locators: [EntryLocator]? = nil) {
    self._locators = locators
    super.init(cache: cache, svc: svc)
  }

  func done(_ error: Error? = nil) {
    os_log("done: %{public}@", log: BrowseLog.log, type: .debug,
           error != nil ? String(reflecting: error) : "OK")

    let er = isCancelled ? FeedKitError.cancelledByUser : error
    if let cb = self.entriesCompletionBlock {
      target.async {
        cb(er)
      }
    }
    entriesBlock = nil
    entriesCompletionBlock = nil
    isFinished = true
  }

  /// Request all entries of listed feed URLs remotely.
  ///
  /// - Parameters:
  ///   - locators: The locators of entries to request.
  func request(_ locators: [EntryLocator]) throws {
    os_log("requesting: %{public}@", log: BrowseLog.log, type: .debug, locators)

    let reload = ttl == .none

    task = try svc.entries(locators, reload: reload) { error, payload in
      self.post(name: Notification.Name.FKRemoteResponse)

      guard !self.isCancelled else { return self.done() }

      guard error == nil else {
        return self.done(FeedKitError.serviceUnavailable(error: error!))
      }

      guard payload != nil else {
        os_log("no payload", log: BrowseLog.log)
        return self.done()
      }

      os_log("received payload", log: BrowseLog.log, type: .debug)

      do {
        let (errors, receivedEntries) = serialize.entries(from: payload!)

        if !errors.isEmpty {
          os_log("invalid entries: %{public}@", log: BrowseLog.log,  type: .error, errors)
        }
        os_log("received: %{public}@", log: BrowseLog.log, type: .debug, receivedEntries)

        let redirected = BrowseOperation.redirects(in: receivedEntries)
        if !redirected.isEmpty {
          os_log("removing redirected: %{public}@", log: BrowseLog.log,
                 String(reflecting: redirected))

          let urls = redirected.reduce([String]()) { acc, entry in
            guard let url = entry.originalURL, !acc.contains(url) else {
              return acc
            }
            return acc + [url]
          }
          try self.cache.remove(urls)
        }

        try self.cache.update(entries: receivedEntries)

        guard let cb = self.entriesBlock, !receivedEntries.isEmpty else {
          return self.done()
        }

        // The cached entries, contrary to the freshly received entries, have
        // more properties. Also, we should not dispatch more entries than
        // those that actually have been requested. To match these requirements
        // centrally, we retrieve the freshly updated entries from the cache,
        // relying on SQLite’s speed.

        let (cached, missing) = try EntriesOperation.entries(
          in: self.cache, locators: self.locators, ttl: .infinity)

        let error: FeedKitError? = {
          guard !missing.isEmpty else {
            return nil
          }
          return FeedKitError.missingEntries(locators: missing)
        }()

        let entries = cached.filter {
          !self.dispatched.contains($0.guid)
        }

        self.target.async() {
          cb(error, entries)
        }
        self.dispatched = self.dispatched + entries.map { $0.guid }
        self.done()
      } catch FeedKitError.feedNotCached(let urls) {
        os_log("feeds not cached: %{public}@", log: BrowseLog.log, urls)
        self.done()
      } catch let er {
        self.done(er)
      }
    }
  }

  override func start() {
    guard !isCancelled else { return done() }
    isExecuting = true

    os_log("EntriesOperation: start: %{public}@", log: BrowseLog.log,
           type: .debug, locators)

    do {
      let target = self.target
      let entriesBlock = self.entriesBlock

      let (cached, missing) = try EntriesOperation.entries(
        in: cache, locators: locators, ttl: ttl.seconds)

      os_log("cached: %{public}@", log: BrowseLog.log, type: .debug, cached)
      os_log("missing: %{public}@", log: BrowseLog.log, type: .debug, missing)

      guard !isCancelled else { return done() }

      if let cb = entriesBlock, !cached.isEmpty {
        target.async {
          cb(nil, cached)
        }
        dispatched = cached.map { $0.guid }
      }

      guard !missing.isEmpty else {
        return done()
      }

      if !reachable {
        done(FeedKitError.offline)
      } else {
        try request(missing)
      }
    } catch {
      done(error)
    }
  }
}

// MARK: Accessing Cached Entries

extension EntriesOperation {

  /// Queries the local `cache` for entries and returns a tuple of cached
  /// entries and unfullfilled entry `locators`, if any.
  ///
  /// - Parameters:
  ///   - cache: The cache object to retrieve entries from.
  ///   - locators: The selection of entries to fetch.
  ///   - ttl: The maximum age of entries to use.
  ///
  /// - Returns: A tuple of cached entries and URLs not satisfied by the cache.
  ///
  /// - Throws: Might throw database errors.
  static func entries(in cache: FeedCaching, locators: [EntryLocator], ttl: TimeInterval)
    throws -> ([Entry], [EntryLocator]) {
      let optimized = EntryLocator.reduce(locators)

      let guids = optimized.flatMap { $0.guid }
      let resolved = try cache.entries(guids)

      guard resolved.count < optimized.count else {
        return (resolved, [])
      }

      let resguids = resolved.map { $0.guid }

      let unresolved = optimized.filter {
        guard let guid = $0.guid else { return true }
        return !resguids.contains(guid)
      }

      let items = try cache.entries(within: unresolved) + resolved
      let unresolvedURLs = unresolved.map { $0.url }

      let (cached, stale, needed) =
        BrowseOperation.subtract(items: items, from: unresolvedURLs, with: ttl)
      assert(stale.isEmpty, "entries cannot be stale")

      let neededLocators: [EntryLocator] = optimized.filter {
        let urls = needed ?? []
        if let guid = $0.guid {
          return !resguids.contains(guid) || urls.contains($0.url)
        }
        return urls.contains($0.url)
      }

      guard neededLocators != optimized else {
        return ([], neededLocators)
      }

      return (cached, neededLocators)
  }

}
