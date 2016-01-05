//
//  search.swift
//  FeedKit
//
//  Created by Michael Nisi on 03.11.14.
//  Copyright (c) 2014 Michael Nisi. All rights reserved.
//

import Foundation
import FanboyKit

/// Use this function to sanitize a search term before passing it to the search
/// repository.
///
/// - Parameter term: The raw search term.
/// - Returns: A lowercase, space-separated representation of the term.
public func sanitizeSearchTerm(term: String) -> String {
  return trimString(term.lowercaseString, joinedByString: " ")
}

class SearchRepoOperation: SessionTaskOperation {
  let cache: SearchCaching
  let svc: FanboyService
  let term: String
  let target: dispatch_queue_t
  
  init(cache: SearchCaching, svc: FanboyService, term: String, target: dispatch_queue_t) {
    self.cache = cache
    self.svc = svc
    self.term = term
    self.target = target
  }
}

final class SearchOperation: SearchRepoOperation {
  
  // MARK: Callbacks
  
  var feedsBlock: ((ErrorType?, [Feed]) -> Void)?
  
  var searchCompletionBlock: ((ErrorType?) -> Void)?
  
  // MARK: State
  
  var stock: [Feed]?
  
  // MARK: Internals
  
  private func request() throws {
    let cache = self.cache
    let term = self.term
    let target = self.target
    let feedsBlock = self.feedsBlock
    let stock = self.stock
    
    task = try svc.search(term) { error, payload in
      guard !self.cancelled else {
        return self.done()
      }
      guard error == nil else {
        if let cb = feedsBlock {
          if let feeds = stock {
            dispatch_async(target) {
              // TODO: Decide where to pass this error
              cb(nil, feeds)
            }
          }
        }
        return self.done(FeedKitError.ServiceUnavailable(error: error!))
      }
      guard payload != nil else {
        return self.done()
      }
      do {
        let feeds = try feedsFromPayload(payload!)
        try cache.updateFeeds(feeds, forTerm: term)
        guard let cb = feedsBlock else {
          return self.done()
        }
        dispatch_async(target) {
          cb(nil, feeds)
        }
        self.done()
      } catch let er {
        self.done(er)
      }
    }
  }
  
  private func done(var error: ErrorType? = nil) {
    if cancelled {
      error = FeedKitError.CancelledByUser
    }
    let block = self.searchCompletionBlock
    dispatch_async(target) {
      guard let cb = block else {
        return
      }
      cb(error)
    }
    feedsBlock = nil
    searchCompletionBlock = nil
    finished = true
  }
  
  override func start() {
    if cancelled {
      return done()
    }
    executing = true
    do {
      guard let cb = feedsBlock else {
        return try request()
      }
      // TODO: Fit a limit
      let cached = try cache.feedsForTerm(term, limit: 25)
      if cancelled {
        return done()
      }
      if let c = cached {
        if let ts = c.first?.ts {
          if !stale(ts, ttl: cache.ttl.long) {
            dispatch_async(target) {
              cb(nil, c)
            }
            return done()
          } else {
            stock = c
          }
        } else {
          return done()
        }
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

final class SuggestOperation: SearchRepoOperation {
  
  // MARK: Callbacks
  
  var perFindGroupBlock: ((ErrorType?, [Find]) -> Void)?
  
  var suggestCompletionBlock: ((ErrorType?) -> Void)?
  
  // MARK: State
  
  /// An array to keep track of finds that have been dispatched, to prevent doublings.
  final var dispatched = [Find]()
  
  // Stale suggestions from the cache.
  var stock: [Suggestion]?
  
  /// This is `true` if a remote request is required.
  var requestRequired: Bool = false
  
  // MARK: Internals
  
  private func done(var error: ErrorType? = nil) {
    if cancelled {
      error = FeedKitError.CancelledByUser
    }
    let block = self.suggestCompletionBlock
    dispatch_async(target) { 
      guard let cb = block else {
        return
      }
      cb(error)
    }
    perFindGroupBlock = nil
    suggestCompletionBlock = nil
    finished = true
  }
  
  private func request() throws {
    let target = self.target
    let term = self.term
    let stock = self.stock
    let perFindGroupBlock = self.perFindGroupBlock
    
    try svc.suggest(term) { er, suggestions in
      guard er == nil else {
        defer {
          self.done(er)
        }
        if let fallback = stock {
          if fallback.isEmpty {
            return
          }
          let finds = fallback.map { Find.SuggestedTerm($0) }
          dispatch_async(target) {
            guard let cb = perFindGroupBlock else {
              return
            }
            cb(nil, finds)
          }
        }
        return
      }
      
      if let sugs = suggestions {
        let new = suggestionsFromTerms(sugs)
        do {
          try self.cache.updateSuggestions(new, forTerm: term)
          defer {
            self.done()
          }
          guard !new.isEmpty else {
            return
          }
          let finds = new.map { Find.SuggestedTerm($0) }
          dispatch_async(target) {
            guard let cb = perFindGroupBlock else {
              return
            }
            cb(nil, finds)
          }
          self.dispatched += finds
        } catch let er {
          self.done(er)
        }
      } else {
        self.done()
      }
    }
  }
  
  private func resume() {
    var error: ErrorType?
    
    defer {
      if requestRequired {
        do {
          try request()
        } catch let er {
          done(er)
        }
      } else {
        done(error)
      }
    }
    
    guard let perFindGroupBlock = self.perFindGroupBlock else {
      return
    }
    
    let funs = [
      recentSearchesForTerm,
      suggestedFeedsForTerm,
      suggestedEntriesForTerm
    ]
    for f in funs {
      if cancelled {
        return done()
      }
      do {
        if let finds = try f(term, fromCache: cache, except: dispatched) {
          guard !finds.isEmpty else {
            return
          }
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
    if cancelled {
      return done()
    }
    executing = true
    do {
      guard let cb = self.perFindGroupBlock else {
        requestRequired = true
        return resume()
      }
      if let cs = try cache.suggestionsForTerm(term, limit: 4) {
        if cancelled {
          return done()
        }
        if let ts = cs.first?.ts { // assuming all have the same timestamp
          if !stale(ts, ttl: cache.ttl.long) {
            let finds = cs.map { Find.SuggestedTerm($0) }
            dispatch_async(target) {
              cb(nil, finds)
            }
            dispatched += finds
          } else {
            stock = cs
            requestRequired = true
          }
        }
      } else {
        requestRequired = true
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
  
  public func search(
    term: String,
    feedsBlock: (ErrorType?, [Feed]) -> Void,
    searchCompletionBlock: (ErrorType?) -> Void
  ) -> NSOperation {
    let target = dispatch_get_main_queue()
    let op = SearchOperation(cache: cache, svc: svc, term: term, target: target)
    op.feedsBlock = feedsBlock
    op.searchCompletionBlock = searchCompletionBlock
    queue.addOperation(op)
    return op
  }
  
  // TODO: Consider using specific callbacks per group
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