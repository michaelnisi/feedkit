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
  var entries: Set<Entry> { get }
}

// MARK: - Entries

/// Comply with MangerKit API to enable using the remote service.
extension EntryLocator: MangerQuery {}

final class EntriesOperation: BrowseOperation, ProvidingEntries {

  // MARK: ProvidingEntries

  private(set) var error: Error?
  private(set) var entries = Set<Entry>()

  // MARK: Callbacks

  var entriesBlock: ((Error?, [Entry]) -> Void)?
  var entriesCompletionBlock: ((Error?) -> Void)?

  // MARK: State

  var _locators: [EntryLocator]?

  lazy var locators: [EntryLocator] = {
    guard let locs = _locators else {
      let found = dependencies.reduce([EntryLocator]()) { acc, dep in
        if case let req as ProvidingLocators = dep {
          // TODO: Handle request error
          return acc + req.locators
        }
        return acc
      }

      _locators = found
      return found
    }

    return locs
  }()

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

  /// If we have been cancelled, it’s OK to just say `done()` and be done.
  func done(_ error: Error? = nil) {
    os_log("done: %{public}@", log: Browse.log, type: .debug,
           error != nil ? error! as CVarArg : "ok")

    let er = isCancelled ? FeedKitError.cancelledByUser : error
    
    defer {
      entriesBlock = nil
      entriesCompletionBlock = nil
      isFinished = true
    }
    
    guard let cb = self.entriesCompletionBlock else {
      return
    }
    
    target.async {
      cb(er)
    }
  }

  /// Request all entries of listed feed URLs remotely.
  ///
  /// - Parameters:
  ///   - locators: The locators of entries to request.
  func request(_ locators: [EntryLocator]) throws {
    os_log("requesting: %{public}@", log: Browse.log, type: .debug, locators)

    let reload = ttl == .none

    task = try svc.entries(locators, reload: reload) { error, payload in
      self.post(name: Notification.Name.FKRemoteResponse)

      guard !self.isCancelled else { return self.done() }

      guard error == nil else {
        return self.done(FeedKitError.serviceUnavailable(error: error!))
      }

      guard payload != nil else {
        os_log("no payload", log: Browse.log)
        return self.done()
      }

      os_log("received payload", log: Browse.log, type: .debug)

      do {
        let (errors, receivedEntries) = serialize.entries(from: payload!)

        if !errors.isEmpty {
          os_log("invalid entries: %{public}@", log: Browse.log,  type: .error, errors)
        }
        os_log("received: %{public}@", log: Browse.log, type: .debug, receivedEntries)

        let redirected = BrowseOperation.redirects(in: receivedEntries)
        if !redirected.isEmpty {
          os_log("removing redirected: %{public}@", log: Browse.log,
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

        // TODO: Not correct, cb is not mandatory
        guard let cb = self.entriesBlock, !receivedEntries.isEmpty else {
          return self.done()
        }

        // The cached entries, contrary to the freshly received entries, have
        // more properties. Also, we should not dispatch more entries than
        // those that actually have been requested. To match these requirements
        // centrally, we retrieve the freshly updated entries from the cache,
        // relying on SQLite’s speed.

        let (cached, missing) = try self.cache.fulfill(self.locators, ttl: .infinity)

        let error: FeedKitError? = {
          guard !missing.isEmpty else {
            return nil
          }
          return FeedKitError.missingEntries(locators: missing)
        }()

        let fresh = cached.filter {
          !self.entries.contains($0)
        }
        
        if !fresh.isEmpty {
          self.entries.formUnion(fresh)
        }
        
        if !fresh.isEmpty || error != nil {
          self.target.async() {
            cb(error, fresh)
          }
        }

        self.done()
      } catch FeedKitError.feedNotCached(let urls) {
        os_log("feeds not cached: %{public}@", log: Browse.log, urls)
        self.done()
      } catch let er {
        self.done(er)
      }
    }
  }

  override func start() {
    guard !isCancelled else { return done() }
    isExecuting = true

    os_log("EntriesOperation: start: %{public}@", log: Browse.log,
           type: .debug, locators)

    do {
      let (cached, missing) = try cache.fulfill(locators, ttl: ttl.seconds)

      os_log("cached: %{public}@", log: Browse.log, type: .debug, cached)
      os_log("missing: %{public}@", log: Browse.log, type: .debug, missing)

      guard !isCancelled else { return done() }

      if !cached.isEmpty {
        entries.formUnion(cached)
        if let cb = entriesBlock {
          target.async {
            cb(nil, cached)
          }
        }
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
