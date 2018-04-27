//
//  search.swift
//  FeedKit
//
//  Created by Michael Nisi on 03.11.14.
//  Copyright (c) 2014 Michael Nisi. All rights reserved.
//

import Foundation
import os.log

struct Search {
  static var log = OSLog(subsystem: "ink.codes.feedkit", category: "search")
}

// MARK: - Suggestion

/// A suggested search term, bearing the timestamp of when it was added
/// (to the cache) or updated.
public struct Suggestion {
  public let term: String
  public var ts: Date? // if cached
}

extension Suggestion : CustomStringConvertible {
  public var description: String {
    return "Suggestion: \(term) \(String(describing: ts))"
  }
}

extension Suggestion: Equatable {
  static public func ==(lhs: Suggestion, rhs: Suggestion) -> Bool {
    return lhs.term == rhs.term
  }
}

extension Suggestion: Hashable {
  public var hashValue: Int {
    get { return term.hashValue }
  }
}

// MARK: - Find

// Supplied by a single UITableViewDataSource class. Or maybe two, like Find and
// Item, but the question is: how different would they be, really? Considering
// that with an holistic search, the kind we want to offer, a Find may be
// literally anything in the system. Doesn’t this make Find just an Item? To
// figure this out, create item lists of all expected combinations.
//
// A couple of days later, I’m not convinced about this—a global master thing
// always ends in flames, not a good argument, I know, but all I muster to come
// up with now. Keep enumerating for specific needs!

/// Enumerates findable things hiding their type. The word 'suggested' is used
/// synonymously with 'found' here: a suggested feed is also a found feed, etc.
public enum Find {
  case recentSearch(Feed)
  case suggestedTerm(Suggestion)
  case suggestedEntry(Entry)
  case suggestedFeed(Feed)
  case foundFeed(Feed)
  
  /// The timestamp applied by the database.
  var ts: Date? {
    switch self {
    case .recentSearch(let it): return it.ts
    case .suggestedTerm(let it): return it.ts
    case .suggestedEntry(let it): return it.ts
    case .suggestedFeed(let it): return it.ts
    case .foundFeed(let it): return it.ts
    }
  }
}

extension Find: Equatable {
  static public func ==(lhs: Find, rhs: Find) -> Bool {
    switch (lhs, rhs) {
    case (.suggestedEntry(let a), .suggestedEntry(let b)):
      return a == b
    case (.suggestedTerm(let a), .suggestedTerm(let b)):
      return a == b
    case (.suggestedFeed(let a), .suggestedFeed(let b)):
      return a == b
    case (.recentSearch(let a), .recentSearch(let b)):
      return a == b
    case (.foundFeed(let a), .foundFeed(let b)):
      return a == b
    case (.suggestedEntry, _),
         (.suggestedTerm, _),
         (.suggestedFeed, _),
         (.recentSearch, _),
         (.foundFeed, _):
      return false
    }
  }
}

extension Find: Hashable {
  public var hashValue: Int {
    get {
      switch self {
      case .foundFeed(let feed),
           .recentSearch(let feed),
           .suggestedFeed(let feed):
        return feed.hashValue
      case .suggestedEntry(let entry):
        return entry.hashValue
      case .suggestedTerm(let suggestion):
        return suggestion.hashValue
      }
    }
  }
}

// MARK: - SearchCaching

/// A persistent cache of things related to searching feeds and entries.
public protocol SearchCaching {
  func update(suggestions: [Suggestion], for term: String) throws
  func suggestions(for term: String, limit: Int) throws -> [Suggestion]?
  
  func update(feeds: [Feed], for: String) throws
  func feeds(for term: String, limit: Int) throws -> [Feed]?
  func feeds(matching term: String, limit: Int) throws -> [Feed]?
  func entries(matching term: String, limit: Int) throws -> [Entry]?
}

// MARK: - Searching

/// The search API of the FeedKit framework.
public protocol Searching {
  
  /// Search for feeds by term using locally cached data requested from a remote
  /// service. This method falls back on cached data if the remote call fails;
  /// the failure is reported by passing an error in the completion block.
  ///
  /// - Parameters:
  ///   - term: The term to search for or a feed URL.
  ///   - perFindGroupBlock: The block to receive finds.
  ///   - searchCompletionBlock: The block to execute after the search
  /// is complete.
  ///
  /// - returns: The, already executing, operation.
  @discardableResult func search(
    _ term: String,
    perFindGroupBlock: ((Error?, [Find]) -> Void)?,
    searchCompletionBlock: ((Error?) -> Void)?
  ) -> Operation
  
  /// Get lexicographical suggestions for a search term combining locally cached
  /// and remote data.
  ///
  /// - Parameters:
  ///   - term: The term to search for.
  ///   - perFindGroupBlock: The block to receive finds, called once
  ///   per find group as enumerated in `Find`.
  ///   - suggestCompletionBlock: A block called when the operation has finished.
  ///
  /// - Returns: The, already executing, operation.
  @discardableResult func suggest(
    _ term: String,
    perFindGroupBlock: ((Error?, [Find]) -> Void)?,
    suggestCompletionBlock: ((Error?) -> Void)?
  ) -> Operation
  
}
