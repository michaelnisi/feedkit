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

  private func findLocators() throws -> [EntryLocator] {
    var found = Set<EntryLocator>()
    for dep in dependencies {
      if case let req as ProvidingLocators = dep {
        guard req.error == nil else {
          throw req.error!
        }
        found.formUnion(req.locators)
      }
    }
    return Array(found)
  }

  var _locators: [EntryLocator]?
  lazy var locators: [EntryLocator] = {
    guard let locs = _locators else {
      do {
        _locators = try findLocators()
      } catch {
        self.error = error
      }
      return _locators!
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
  
  deinit {
    os_log("** deinit", type: .debug)
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

        let r = Entry.redirects(in: receivedEntries)
        if !r.isEmpty {
          let urls = r.map { $0.originalURL! }
          try self.cache.remove(urls)
        }

        try self.cache.update(entries: receivedEntries)

        guard !receivedEntries.isEmpty else {
          return self.done()
        }

        // The cached entries, contrary to the freshly received entries, have
        // more properties. Also, we should not dispatch more entries than
        // those that actually have been requested. To match these requirements
        // centrally, we retrieve the freshly updated entries from the cache,
        // relying on SQLite’s speed.
        
        // TODO: Review
        
        // Range locators, without guids, as used while updating the Queue,
        // apparently don’t work here. I get ([], [locators]).

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

        if (!fresh.isEmpty || error != nil), let cb = self.entriesBlock {
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
    guard !isCancelled, error == nil, !locators.isEmpty else {
      return done(error)
    }
    isExecuting = true

    do {
      os_log("trying cache: %{public}@", log: Browse.log,
             type: .debug, locators)

      let (cached, missing) = try cache.fulfill(locators, ttl: ttl.seconds)

      guard !isCancelled else { return done() }

      os_log("cached: %{public}@", log: Browse.log, type: .debug, cached)
      os_log("missing: %{public}@", log: Browse.log, type: .debug, missing)

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
