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
  ///   - term: The term to search for.
  ///   - perFindGroupBlock: The block to receive finds.
  ///   - searchCompletionBlock: The block to execute after the search
  /// is complete.
  ///
  /// - returns: The, already executing, operation.
  @discardableResult func search(
    _ term: String,
    perFindGroupBlock: @escaping (Error?, [Find]) -> Void,
    searchCompletionBlock: @escaping (Error?) -> Void
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
    perFindGroupBlock: @escaping (Error?, [Find]) -> Void,
    suggestCompletionBlock: @escaping (Error?) -> Void
  ) -> Operation
  
}
