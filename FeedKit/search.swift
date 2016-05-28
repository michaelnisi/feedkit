//
//  search.swift
//  FeedKit
//
//  Created by Michael Nisi on 03.11.14.
//  Copyright (c) 2014 Michael Nisi. All rights reserved.
//

// TODO: Add ranking to improve top hits

import Foundation
import FanboyKit

/// An abstract class to be extended by search repository operations.
private class SearchRepoOperation: SessionTaskOperation {

  let cache: SearchCaching
  let originalTerm: String
  let svc: FanboyService
  let term: String
  let target: dispatch_queue_t

  /// Returns an initialized search repo operation.
  ///
  /// - Parameter cache: A persistent search cache.
  /// - Parameter svc: The remote search service to use.
  /// - Parameter term: The term to search—or get suggestions—for; it can be any
  /// string.
  /// - Parameter target: The target dispatch queue for callbacks.
  init(
    cache: SearchCaching,
    svc: FanboyService,
    term: String,
    target: dispatch_queue_t
  ) {
    self.cache = cache
    self.originalTerm = term
    self.svc = svc
    self.term = trimString(term.lowercaseString, joinedByString: " ")
    self.target = target
  }
}

// Search feeds and entries.
private final class SearchOperation: SearchRepoOperation {

  // MARK: Callbacks

  var perFindGroupBlock: ((ErrorType?, [Find]) -> Void)?

  var searchCompletionBlock: ((ErrorType?) -> Void)?

  // MARK: State

  /// Stale feeds from the cache.
  var stock: [Feed]?

  private func done( error: ErrorType? = nil) {
    let er = cancelled ? FeedKitError.CancelledByUser : error
    if let cb = searchCompletionBlock {
      dispatch_async(target) {
        cb(er)
      }
    }
    perFindGroupBlock = nil
    searchCompletionBlock = nil
    finished = true
  }

  // MARK: Internals

  /// Remotely request search and subsequently update the cache while falling
  /// back on stale feeds in stock. Finally end the operation after applying
  /// the callback. Remember that stock must not be empty.
  private func request() throws {
    let cache = self.cache
    let perFindGroupBlock = self.perFindGroupBlock
    let stock = self.stock
    let target = self.target
    let term = self.term

    task = try svc.search(term) { error, payload in
      guard !self.cancelled else {
        return self.done()
      }
      guard error == nil else {
        defer {
          let er = FeedKitError.ServiceUnavailable(error: error!)
          self.done(er)
        }
        if let cb = perFindGroupBlock {
          if let feeds = stock {
            guard !feeds.isEmpty else { return }
            // TODO: Consider to enumerate a found feed type
            let finds = feeds.map { Find.SuggestedFeed($0) }
            dispatch_async(target) {
              cb(nil, finds)
            }
          }
        }
        return
      }
      guard payload != nil else {
        return self.done()
      }
      do {
        let (errors, feeds) = feedsFromPayload(payload!)
        // TODO: Report errors
        assert(errors.isEmpty)
        try cache.updateFeeds(feeds, forTerm: term)
        guard !feeds.isEmpty else { return self.done() }
        guard let cb = perFindGroupBlock else { return self.done() }
        let finds = feeds.map { Find.SuggestedFeed($0) }
        dispatch_async(target) {
          cb(nil, finds)
        }
        self.done()
      } catch let er {
        self.done(er)
      }
    }
  }

  override func start() {
    guard !cancelled else { return done() }
    guard !term.isEmpty else {
      return done(FeedKitError.InvalidSearchTerm(term: term))
    }
    executing = true
    do {
      guard let cached = try cache.feedsForTerm(term, limit: 25) else {
        return try request()
      }
      if cancelled { return done() }
      // This is not the timestamp of the feed but of the search, hence all
      // cached feeds carry the same timestamp here, and we just have to check
      // the first one.
      guard let ts = cached.first?.ts else { return done() }
      if !stale(ts, ttl: CacheTTL.Long.seconds) {
        guard let cb = perFindGroupBlock else { return done() }
        let finds = cached.map { Find.SuggestedFeed($0) }
        dispatch_async(target) {
          cb(nil, finds)
        }
        return done()
      } else {
        stock = cached
      }
      try request()
    } catch let er {
      done(er)
    }
  }
}

private func recentSearchesForTerm(
  term: String,
  fromCache cache: SearchCaching,
  except exceptions: [Find]
) throws -> [Find]? {
  if let feeds = try cache.feedsForTerm(term, limit: 2) {
    return feeds.reduce([Find]()) { acc, feed in
      let find = Find.RecentSearch(feed)
      if exceptions.contains(find) {
        return acc
      } else {
        return acc + [find]
      }
    }
  }
  return nil
}

func suggestedFeedsForTerm(
  term: String,
  fromCache cache: SearchCaching,
  except exceptions: [Find]
) throws -> [Find]? {
  let limit = 5
  if let feeds = try cache.feedsMatchingTerm(term, limit: limit + 2) {
    return feeds.reduce([Find]()) { acc, feed in
      let find = Find.SuggestedFeed(feed)
      if exceptions.contains(find) || acc.count == limit {
        return acc
      } else {
        return acc + [find]
      }
    }
  }
  return nil
}

func suggestedEntriesForTerm(
  term: String,
  fromCache cache: SearchCaching,
  except exceptions: [Find]
) throws -> [Find]? {
  if let entries = try cache.entriesMatchingTerm(term, limit: 5) {
    return entries.reduce([Find]()) { acc, entry in
      let find = Find.SuggestedEntry(entry)
      if exceptions.contains(find) {
        return acc
      } else {
        return acc + [find]
      }
    }
  }
  return nil
}

func suggestionsFromTerms(terms: [String]) -> [Suggestion] {
  return terms.map { Suggestion(term: $0, ts: nil) }
}

// An operation to get search suggestions.
private final class SuggestOperation: SearchRepoOperation {

  // MARK: Callbacks

  var perFindGroupBlock: ((ErrorType?, [Find]) -> Void)?

  var suggestCompletionBlock: ((ErrorType?) -> Void)?

  // MARK: State

  /// An array to keep track of finds that have been dispatched to prevent
  /// doublings.
  var dispatched = [Find]()

  /// Stale suggestions from the cache.
  var stock: [Suggestion]?

  /// This is `true` if a remote request is required.
  var requestRequired: Bool = true

  // MARK: Internals

  private func done(error: ErrorType? = nil) {
    let er = cancelled ?  FeedKitError.CancelledByUser : error
    if let cb = suggestCompletionBlock {
      dispatch_async(target) {
        cb(er)
      }
    }
    perFindGroupBlock = nil
    suggestCompletionBlock = nil
    finished = true
  }

  private func request() throws {
    let cache = self.cache
    let dispatched = self.dispatched
    let perFindGroupBlock = self.perFindGroupBlock
    let stock = self.stock
    let target = self.target
    let term = self.term

    task = try svc.suggest(term) { error, payload in
      guard !self.cancelled else {
        return self.done()
      }
      guard error == nil else {
        defer {
          let er = FeedKitError.ServiceUnavailable(error: error!)
          self.done(er)
        }
        if let cb = perFindGroupBlock {
          if let suggestions = stock {
            guard !suggestions.isEmpty else { return }
            let finds = suggestions.map { Find.SuggestedTerm($0) }
            dispatch_async(target) {
              cb(nil, finds)
            }
          }
        }
        return
      }
      guard payload != nil else {
        return self.done()
      }
      do {
        let suggestions = suggestionsFromTerms(payload!)
        try cache.updateSuggestions(suggestions, forTerm: term)
        guard !suggestions.isEmpty else { return self.done() }
        guard let cb = perFindGroupBlock else { return self.done() }
        let finds = suggestions.reduce([Find]()) { acc, sug in
          let find = Find.SuggestedTerm(sug)
          if dispatched.contains(find) { return acc }
          return acc + [find]
        }
        guard !finds.isEmpty else { return self.done() }
        dispatch_async(target) {
          cb(nil, finds)
        }
        // At the moment it is unnecessary to append our finds to the
        // dispatched list because we are done now.
        self.done()
      } catch let er {
        self.done(er)
      }
    }
  }

  private func resume() {
    var error: ErrorType?
    defer {
      if requestRequired {
        do { try request() } catch let er { done(er) }
      } else {
        done(error)
      }
    }
    guard let perFindGroupBlock = self.perFindGroupBlock else { return }
    let funs = [
      recentSearchesForTerm,
      suggestedFeedsForTerm,
      suggestedEntriesForTerm
    ]
    for f in funs {
      if cancelled { return done() }
      do {
        if let finds = try f(term, fromCache: cache, except: dispatched) {
          guard !finds.isEmpty else { return }
          dispatch_async(target) {
            perFindGroupBlock(nil, finds)
          }
          dispatched += finds
        }
      } catch let er {
        return error = er
      }
    }
  }

  override func start() {
    guard !cancelled else { return done() }
    guard !term.isEmpty else {
      return done(FeedKitError.InvalidSearchTerm(term: term))
    }
    executing = true
    do {
      guard let cb = self.perFindGroupBlock else { return resume() }

      let sug = Suggestion(term: originalTerm, ts: nil)
      let original = Find.SuggestedTerm(sug)

      func dispatchOriginal() {
        let finds = [original]
        // TODO: Review über correct dispatch block
        dispatch_async(target) { [weak self] in
          guard let me = self else { return }
          guard !me.cancelled else { return }
          guard let cb = me.perFindGroupBlock else { return }
          cb(nil, finds)
        }
        dispatched += finds
      }

      guard let cached = try cache.suggestionsForTerm(term, limit: 4) else {
        dispatchOriginal()
        return resume()
      }
      if cancelled { return done() }
      // See timestamp comment in SearchOperation.
      guard let ts = cached.first?.ts else {
        dispatchOriginal()
        requestRequired = false
        return resume()
      }
      if !stale(ts, ttl: CacheTTL.Long.seconds) {
        let finds = [original] + cached.map { Find.SuggestedTerm($0) }
        dispatch_async(target) {
          cb(nil, finds)
        }
        dispatched += finds
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

/// The search repository provides a search API orchestrating remote services
/// and persistent caching.
public final class SearchRepository: Searching {

  let cache: SearchCaching
  let svc: FanboyService
  let queue: NSOperationQueue

  /// Initializes and returns search repository object.
  ///
  /// - Parameter cache: The search cache.
  /// - Parameter queue: An operation queue to run the search operations.
  /// - Parameter svc: The fanboy service to handle remote queries.
  public init(cache: SearchCaching, queue: NSOperationQueue, svc: FanboyService) {
    self.cache = cache
    self.queue = queue
    self.svc = svc
  }

  /// Search for feeds by term using a locally cached data requested from a
  /// remote service. This method falls back on cached data, if the remote call
  /// fails, the failure is reported by passing an error in the completion block.
  ///
  /// - Parameter term: The term to search for.
  /// - Parameter perFindGroupBlock: The block to receive finds.
  /// - Parameter searchCompletionBlock: The block to execute after the
  ///   search is complete.
  public func search(
    term: String,
    perFindGroupBlock: (ErrorType?, [Find]) -> Void,
    searchCompletionBlock: (ErrorType?) -> Void
  ) -> NSOperation {
    let target = dispatch_get_main_queue()
    let op = SearchOperation(cache: cache, svc: svc, term: term, target: target)
    op.perFindGroupBlock = perFindGroupBlock
    op.searchCompletionBlock = searchCompletionBlock
    queue.addOperation(op)
    return op
  }

  /// Get lexicographical suggestions for a search term combining locally cached
  /// and remote data.
  ///
  /// - Parameter term: The search term.
  /// - Parameter perFindGroupBlock: The block to receive finds - called once
  ///   per find group as enumerated in `Find`.
  /// - Parameter completionBlock: A block called when the operation has finished.
  public func suggest(
    term: String,
    perFindGroupBlock: (ErrorType?, [Find]) -> Void,
    suggestCompletionBlock: (ErrorType?) -> Void
  ) -> NSOperation {
    let target = dispatch_get_main_queue()
    let op = SuggestOperation(cache: cache, svc: svc, term: term, target: target)
    op.perFindGroupBlock = perFindGroupBlock
    op.suggestCompletionBlock = suggestCompletionBlock
    queue.addOperation(op)
    return op
  }
}
