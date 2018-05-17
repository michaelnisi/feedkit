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

/// A concurrent `Operation` for accessing entries.
final class EntriesOperation: BrowseOperation, LocatorsDependent, ProvidingEntries {

  // MARK: ProvidingEntries

  private(set) var error: Error?
  private(set) var entries = Set<Entry>()

  // MARK: Callbacks

  var entriesBlock: ((Error?, [Entry]) -> Void)?
  var entriesCompletionBlock: ((Error?) -> Void)?

  private var _locators: [EntryLocator]?
  private lazy var locators: [EntryLocator] = {
    guard let locs = _locators else {
      do {
        _locators = try findLocators()
      } catch {
        switch error {
        case ProvidingError.missingLocators:
          fatalError(String(describing: error))
        default:
          self.error = error
          _locators = []
        }
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
  
  private func submit(_ otherEntries: [Entry], error: Error? = nil) {
    if error == nil {
      assert(!otherEntries.isEmpty)
    }
    entries.formUnion(otherEntries)
    entriesBlock?(error, otherEntries)
  }
  
  /// If we have been cancelled, it’s OK to just say `done()` and be done.
  private func done(_ error: Error? = nil) {
    let er: Error? = {
      guard !isCancelled else {
        return FeedKitError.cancelledByUser
      }
      self.error = self.error ?? error
      return self.error
    }()
    

    entriesCompletionBlock?(er)
    
    entriesBlock = nil
    entriesCompletionBlock = nil
    task = nil

    isFinished = true
  }

  /// Request all entries of listed feed URLs remotely.
  ///
  /// - Parameters:
  ///   - locators: The locators of entries to request.
  private func request(_ locators: [EntryLocator]) throws {
    os_log("requesting: %{public}@", log: Browse.log, type: .debug, locators)

    let reload = ttl == .none

    let cache = self.cache

    task = try svc.entries(locators, reload: reload) {
      [weak self] error, payload in
      guard let me = self, !me.isCancelled else {
        self?.done()
        return
      }

      guard error == nil else {
        self?.done(FeedKitError.serviceUnavailable(error!))
        return
      }

      guard payload != nil else {
        os_log("no payload", log: Browse.log)
        self?.done()
        return
      }

      os_log("received payload", log: Browse.log, type: .debug)

      do {
        let (errors, receivedEntries) = serialize.entries(from: payload!)
        
        guard !me.isCancelled else { return me.done() }

        if !errors.isEmpty {
          os_log("invalid entries: %{public}@", log: Browse.log,  type: .error,
                 errors)
        }
        
        os_log("received: %{public}@", log: Browse.log, type: .debug,
               receivedEntries)
        
        guard !receivedEntries.isEmpty else {
          self?.done()
          return
        }
        
        // Handling HTTP Redirects

        let r = Entry.redirects(in: receivedEntries)
        if !r.isEmpty {
          let urls = r.map { $0.originalURL! }
          try cache.remove(urls)
        }
    
        try cache.update(entries: receivedEntries)
        
        guard !me.isCancelled else { return me.done() }
        
        // Preparing Result

        // The cached entries, contrary to the freshly received entries, have
        // more properties. Also, we should not dispatch more entries than
        // those that actually have been requested. To match these requirements
        // centrally, we retrieve the freshly updated entries from the cache,
        // relying on SQLite’s speed.

        let (cached, missing) = try cache.fulfill(locators, ttl: .infinity)
        
        guard !me.isCancelled else { return me.done() }

        let error: FeedKitError? = {
          guard !missing.isEmpty else {
            return nil
          }
          return FeedKitError.missingEntries(locators: missing)
        }()
        
        let a = Set(cached)
        let b = self?.entries ?? Set<Entry>()
        let fresh = Array(a.subtracting(b))
        
        if !fresh.isEmpty {
          if (!fresh.isEmpty) {
            self?.submit(fresh, error: error)
          }
        } else if error != nil {
          self?.submit([], error: error)
        }

        self?.done()
      } catch FeedKitError.feedNotCached(let urls) {
        os_log("feeds not cached: %{public}@", log: Browse.log, urls)
        self?.done()
      } catch {
        self?.done(error)
      }
    }
  }

  override func start() {
    os_log("starting EntriesOperation", log: Browse.log, type: .debug)
    
    guard !isCancelled else { return done() }
    isExecuting = true
    
    guard error == nil, !locators.isEmpty else {
      os_log("aborting EntriesOperation: no locators provided",
             log: Browse.log, type: .debug)
      return done(error)
    }
    
    do {
      os_log("trying cache: %{public}@", log: Browse.log, type: .debug, locators)

      let (cached, missing) = try cache.fulfill(locators, ttl: ttl.seconds)

      guard !isCancelled else { return done() }

      os_log("""
        ttl: %f,
        cached: %{public}@,
        missing: %{public}@
      """, log: Browse.log, type: .debug,
           ttl.seconds,
           cached.map { $0.url },
           missing
      )

      if !cached.isEmpty {
        submit(cached)
      }

      guard !missing.isEmpty else {
        return done()
      }

      if !isAvailable {
        done(FeedKitError.offline)
      } else {
        try request(missing)
      }
    } catch {
      done(error)
    }
  }
}
