//
//  search.swift
//  FeedKit
//
//  Created by Michael Nisi on 03.11.14.
//  Copyright (c) 2014 Michael Nisi. All rights reserved.
//

import Foundation
import FanboyKit
import Ola
import os.log

fileprivate let log = OSLog(subsystem: "ink.codes.feedkit", category: "search")

/// An abstract class to be extended by search repository operations.
private class SearchRepoOperation: SessionTaskOperation {

  let cache: SearchCaching
  let originalTerm: String
  let svc: FanboyService
  let term: String
  let target: DispatchQueue

  /// Returns an initialized search repo operation.
  /// 
  /// - Parameters:
  ///   - cache: A persistent search cache.
  ///   - svc: The remote search service to use.
  ///   - term: The term to search—or get suggestions—for; it can be any
  ///   string.
  init(
    cache: SearchCaching,
    svc: FanboyService,
    term: String
  ) {
    self.cache = cache
    self.originalTerm = term
    self.svc = svc
    
    let trimmed = replaceWhitespaces(in: term.lowercased(), with: " ")
    
    self.term = trimmed
    self.target = OperationQueue.current?.underlyingQueue ?? DispatchQueue.main
  }
}

// MARK: - Searching

/// An operation for searching feeds and entries.
private final class SearchOperation: SearchRepoOperation {

  var perFindGroupBlock: ((Error?, [Find]) -> Void)?

  var searchCompletionBlock: ((Error?) -> Void)?

  /// `FeedKitError.cancelledByUser` overrides passed errors.
  fileprivate func done(_ error: Error? = nil) {
    let er = isCancelled ? FeedKitError.cancelledByUser : error
    if let cb = searchCompletionBlock {
      // Dispatching synchronously here to only let this operation finish
      // after searchCompletionBlock completes.
      target.sync {
        cb(er)
      }
    }
    perFindGroupBlock = nil
    searchCompletionBlock = nil
    isFinished = true
  }

  /// Remotely request search and subsequently update the cache while falling
  /// back on stale feeds in stock. Finally, end the operation after applying
  /// the callback. Passing empty stock makes no sense.
  ///
  /// - Parameter stock: Stock of stale feeds to fall back on.
  fileprivate func request(_ stock: [Feed]? = nil) throws {
    // Capturing self as unowned to crash when we've mistakenly ended the
    // operation, here or somewhere else, inducing the system to release it.
    task = try svc.search(term: term) { [unowned self] payload, error in
      self.post(name: Notification.Name.FKRemoteResponse)

      var er: Error?
      defer {
        self.done(er)
      }

      guard !self.isCancelled else {
        return
      }

      guard error == nil else {
        er = FeedKitError.serviceUnavailable(error: error!)
        if let cb = self.perFindGroupBlock {
          if let feeds = stock {
            guard !feeds.isEmpty else { return }
            let finds = feeds.map { Find.foundFeed($0) }
            self.target.sync() {
              cb(nil, finds)
            }
          }
        }
        return
      }

      guard payload != nil else {
        return
      }

      do {
        let (errors, feeds) = serialize.feeds(from: payload!)

        if !errors.isEmpty {
          os_log("JSON parse errors: %{public}@", log: log,  type: .error, errors)
        }

        try self.cache.update(feeds: feeds, for: self.term)
        guard !feeds.isEmpty else {
          return
        }
        guard let cb = self.perFindGroupBlock else {
          return
        }
        let finds = feeds.map { Find.foundFeed($0) }
        self.target.sync() {
          cb(nil, finds)
        }
      } catch let error {
        er = error
      }
    }
  }

  override func start() {
    guard !isCancelled else {
      return done()
    }
    guard !term.isEmpty else {
      return done(FeedKitError.invalidSearchTerm(term: term))
    }
    isExecuting = true

    do {
      guard let cached = try cache.feeds(for: term, limit: 25) else {
        return try request()
      }

      if isCancelled { return done() }

      // If we match instead of equal, to yield more interesting results, we
      // cannot determine the age of a cached search because we might have
      // multiple differing timestamps. Using the median timestamp to determine
      // age works for both: equaling and matching.

      guard let ts = FeedCache.medianTS(cached) else {
        return done()
      }
      
      let shouldRefresh = FeedCache.stale(ts, ttl: CacheTTL.long.seconds)

      if shouldRefresh {
        try request(cached)
      } else {
        guard let cb = perFindGroupBlock else {
          return done()
        }
        let finds = cached.map { Find.foundFeed($0) }
        target.sync {
          cb(nil, finds)
        }
        return done()
      }
    } catch let er {
      done(er)
    }
  }
}

// MARK: - Suggesting

private func recentSearchesForTerm(
  _ term: String,
  fromCache cache: SearchCaching,
  except exceptions: [Find]
) throws -> [Find]? {
  if let feeds = try cache.feeds(for: term, limit: 2) {
    return feeds.reduce([Find]()) { acc, feed in
      let find = Find.recentSearch(feed)
      if exceptions.contains(find) {
        return acc
      } else {
        return acc + [find]
      }
    }
  }
  return nil
}

private func suggestedFeedsForTerm(
  _ term: String,
  fromCache cache: SearchCaching,
  except exceptions: [Find]
) throws -> [Find]? {
  let limit = 5
  if let feeds = try cache.feeds(matching: term, limit: limit + 2) {
    return feeds.reduce([Find]()) { acc, feed in
      let find = Find.suggestedFeed(feed)
      guard !exceptions.contains(find), acc.count < limit else {
        return acc
      }
      return acc + [find]
    }
  }
  return nil
}

private func suggestedEntriesForTerm(
  _ term: String,
  fromCache cache: SearchCaching,
  except exceptions: [Find]
) throws -> [Find]? {
  if let entries = try cache.entries(matching: term, limit: 5) {
    return entries.reduce([Find]()) { acc, entry in
      let find = Find.suggestedEntry(entry)
      guard !exceptions.contains(find) else {
        return acc
      }
      return acc + [find]
    }
  }
  return nil
}

func suggestionsFromTerms(_ terms: [String]) -> [Suggestion] {
  return terms.map { Suggestion(term: $0, ts: nil) }
}

// An operation to get search suggestions.
private final class SuggestOperation: SearchRepoOperation {

  var perFindGroupBlock: ((Error?, [Find]) -> Void)?

  var suggestCompletionBlock: ((Error?) -> Void)?

  /// A set of finds that have been dispatched by this operation.
  var dispatched = Set<Find>()

  /// Stale suggestions from the cache.
  var stock: [Suggestion]?

  /// This is `true` if a remote request is required, the default.
  var requestRequired: Bool = true

  fileprivate func done(_ error: Error? = nil) {
    let er = isCancelled ?  FeedKitError.cancelledByUser : error
    if let cb = suggestCompletionBlock {
      target.sync {
        cb(er)
      }
    }
    perFindGroupBlock = nil
    suggestCompletionBlock = nil
    isFinished = true
  }

  func dispatch(_ error: FeedKitError?, finds: [Find]) {
    target.sync { [unowned self] in
      guard !self.isCancelled else { return }
      guard let cb = self.perFindGroupBlock else { return }
      cb(error as Error?, finds.filter { !self.dispatched.contains($0) })
      self.dispatched.formUnion(finds)
    }
  }

  fileprivate func request() throws {
    guard reachable else {
      return done(FeedKitError.offline)
    }

    task = try svc.suggestions(matching: term, limit: 10) {
      [unowned self] payload, error in
      
      self.post(name: Notification.Name.FKRemoteResponse)

      var er: Error?
      defer {
        self.done(er)
      }

      guard !self.isCancelled else {
        return
      }

      guard error == nil else {
        er = FeedKitError.serviceUnavailable(error: error!)
        if let suggestions = self.stock {
          guard !suggestions.isEmpty else { return }
          let finds = suggestions.map { Find.suggestedTerm($0) }
          self.dispatch(nil, finds: finds)
        }
        return
      }

      guard payload != nil else {
        return
      }

      do {
        let suggestions = suggestionsFromTerms(payload!)
        try self.cache.update(suggestions: suggestions, for: self.term)
        guard !suggestions.isEmpty else { return }
        let finds = suggestions.reduce([Find]()) { acc, sug in
          guard acc.count < 4 else {
            return acc
          }
          let find = Find.suggestedTerm(sug)
          guard !self.dispatched.contains(find) else {
            return acc
          }
          return acc + [find]
        }
        guard !finds.isEmpty else { return }
        self.dispatch(nil, finds: finds)
      } catch let error {
        er = error
      }
    }
  }

  fileprivate func resume() {
    var error: Error?
    defer {
      if requestRequired {
        do { try request() } catch let er { done(er) }
      } else {
        done(error)
      }
    }
    let funs = [
      recentSearchesForTerm,
      suggestedFeedsForTerm,
      suggestedEntriesForTerm
    ]
    for f in funs {
      if isCancelled {
        return requestRequired = false
      }
      do {
        if let finds = try f(term, cache, Array(dispatched)) {
          guard !finds.isEmpty else { return }
          dispatch(nil, finds: finds)
        }
      } catch let er {
        return error = er
      }
    }
  }

  override func start() {
    guard !isCancelled else {
      return done()
    }
    guard !term.isEmpty else {
      return done(FeedKitError.invalidSearchTerm(term: term))
    }
    isExecuting = true

    do {
      let sug = Suggestion(term: originalTerm, ts: nil)
      let original = Find.suggestedTerm(sug)
      dispatch(nil, finds: [original]) // resulting in five suggested terms

      guard let cached = try cache.suggestions(for: term, limit: 4) else {
        return resume()
      }
      
      if isCancelled {
        return done()
      }
      
      // See timestamp comment in SearchOperation.
      guard let ts = cached.first?.ts else {
        requestRequired = false
        return resume()
      }

      if !FeedCache.stale(ts, ttl: ttl.seconds) {
        let finds = cached.map { Find.suggestedTerm($0) }
        dispatch(nil, finds: finds)
        requestRequired = false
      } else {
        stock = cached
      }
      resume()
    } catch let er {
      done(er)
    }
  }
}

// MARK: - Accessing Search and Suggestions

/// The search repository provides a search API orchestrating remote services
/// and persistent caching.
public final class SearchRepository: RemoteRepository, Searching {
  let cache: SearchCaching
  let svc: FanboyService

  /// Initializes and returns a new search repository object.
  ///
  /// - Parameters:
  ///   - cache: The search cache.
  ///   - queue: An operation queue to run the search operations.
  ///   - svc: The fanboy service to handle remote queries.
  ///   - probe: The probe object to probe reachability.
  public init(
    cache: SearchCaching,
    svc: FanboyService,
    queue: OperationQueue,
    probe: Reaching
  ) {
    self.cache = cache
    self.svc = svc

    super.init(queue: queue, probe: probe)
  }

  /// Configures and adds `operation` to the queue, returns executing operation.
  fileprivate func execute(_ operation: SearchRepoOperation) -> Operation {
    let r = reachable()
    let term = operation.term
    let status = svc.client.status
    
    operation.reachable = r
    operation.ttl = timeToLive(term, force: false, reachable: r, status: status)
    
    queue.addOperation(operation)
    
    return operation
  }

  public func search(
    _ term: String,
    perFindGroupBlock: @escaping (Error?, [Find]) -> Void,
    searchCompletionBlock: @escaping (Error?) -> Void
  ) -> Operation {
    let op = SearchOperation(cache: cache, svc: svc, term: term)
    op.perFindGroupBlock = perFindGroupBlock
    op.searchCompletionBlock = searchCompletionBlock
    return execute(op)
  }

  public func suggest(
    _ term: String,
    perFindGroupBlock: @escaping (Error?, [Find]) -> Void,
    suggestCompletionBlock: @escaping (Error?) -> Void
  ) -> Operation {
    let op = SuggestOperation(cache: cache, svc: svc, term: term)
    op.perFindGroupBlock = perFindGroupBlock
    op.suggestCompletionBlock = suggestCompletionBlock
    return execute(op)
  }
}

// MARK: - Caching

extension SearchRepository: Caching {
  public func flush() throws {
    try cache.flush()
  }
}
