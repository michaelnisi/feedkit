//
//  SearchRepoOperation.swift
//  FeedKit
//
//  Created by Michael Nisi on 15.01.18.
//  Copyright © 2018 Michael Nisi. All rights reserved.
//

import Foundation
import FanboyKit

/// An abstract class to be extended by search repository operations.
class SearchRepoOperation: SessionTaskOperation {
  
  let cache: SearchCaching
  let svc: FanboyService
  let term: String
  
  // A copy of the original query term.
  let originalTerm: String
  
  /// Returns an initialized search repo operation.
  ///
  /// - Parameters:
  ///   - cache: A persistent search cache.
  ///   - svc: The remote search service to use.
  ///   - term: The term to search—or get suggestions—for; it can be any
  ///   string.
  init(cache: SearchCaching, svc: FanboyService, term: String) {
    self.cache = cache
    self.svc = svc
    
    self.originalTerm = term
    self.term = SearchRepoOperation.replaceWhitespaces(in: term.lowercased(), with: " ")
    
    super.init(client: svc.client)
  }
  
}

extension SearchRepoOperation {
  
  /// Remove whitespace from specified string and replace it with `""` or the
  /// specified string. Consecutive spaces are reduced to a single space.
  ///
  /// - Parameters:
  ///   - string: The string to trim..
  ///   - replacement: The string to replace whitespace with.
  ///
  /// - Returns: The trimmed string.
  static func replaceWhitespaces(
    in string: String,
    with replacement: String = ""
    ) -> String {
    let ws = CharacterSet.whitespaces
    let ts = string.trimmingCharacters(in: ws)
    let cmps = ts.components(separatedBy: " ") as [String]
    return cmps.reduce("") { a, b in
      if a.isEmpty { return b }
      let tb = b.trimmingCharacters(in: ws)
      if tb.isEmpty { return a }
      return "\(a)\(replacement)\(tb)"
    }
  }
  
}
