//
//  search.swift
//  FeedKit
//
//  Created by Michael Nisi on 03.11.14.
//  Copyright (c) 2014 Michael Nisi. All rights reserved.
//

import Foundation
import Ola

// Return (optional, but maximal `max`) search items from searchable
// objects `a`, which are not contained in searchable objects `b`,
// where `b` is optional.
func reduceSearchables <T: Searchable>
(a: [T], b: [T]?, max: Int, item: (T) -> SearchItem) -> [SearchItem]? {
  let count = b?.count ?? 0
  var n = max - count
  if n <= 0 {
    return nil
  }
  return a.reduce([SearchItem]()) { items, s in
    guard n-- > 0 else { return items }
    if let c = b {
      if !c.contains(s) {
        return items + [item(s)]
      } else {
        return items
      }
    } else {
      return items + [item(s)]
    }
  }
}

func reduceSuggestions (a: [Suggestion], b: [Suggestion]?, max: Int = 5) -> [SearchItem]? {
  return reduceSearchables(a, b: b, max: max) { sug in
    SearchItem.Sug(sug)
  }
}

func reduceResults (a: [Feed], b: [Feed]?, max: Int = 50) -> [SearchItem]? {
  return reduceSearchables(a, b: b, max: max) { res in
    SearchItem.Res(res)
  }
}

func reduceFeeds (a: [Feed], b: [Feed]?, max: Int = 50) -> [SearchItem]? {
  return reduceSearchables(a, b: b, max: max) { res in
    SearchItem.Fed(res)
  }
}

// TODO: Add Entry




public typealias SearchCallback = (ErrorType?, [SearchItem]) -> Void

// A lowercase, space-separated representation of the string.
public func sanitizeString (s: String) -> String {
  return trimString(s.lowercaseString, joinedByString: " ")
}


private func cancelledByUser (error: NSError) -> Bool {
  return error.code == -999
}

private func reachable (status: OlaStatus, cell:  Bool) -> Bool {
  return status == .Reachable || cell && status == .Cellular
}


