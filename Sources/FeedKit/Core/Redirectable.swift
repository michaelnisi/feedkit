//===----------------------------------------------------------------------===//
//
// This source file is part of the FeedKit open source project
//
// Copyright (c) 2017 Michael Nisi and collaborators
// Licensed under MIT License
//
// See https://github.com/michaelnisi/feedkit/blob/main/LICENSE for license information
//
//===----------------------------------------------------------------------===//

import Foundation

public protocol Redirectable {
  var url: String { get }
  var originalURL: String? { get }
}

extension Redirectable {
  /// Filters and returns `items` with redirected URLs.
  static func redirects(in items: [Redirectable]) -> [Redirectable] {
    items.filter { $0.isRedirected }
  }
  
  var isRedirected: Bool {
    guard let o = originalURL else {
      return false
    }
    return o != url
  }
}

extension Redirectable {
  func isMatching(_ locator: EntryLocator) -> Bool {
    guard
      let originalURL = originalURL,
      let original = URL(string: originalURL),
      let locatorURL = URL(string: locator.url) else {
      return false
    }
    
    return original.host == locatorURL.host && original.pathComponents == locatorURL.pathComponents 
  }
}

extension Array where Element == EntryLocator {
  func relocated(_ redirects: [Redirectable]) -> [EntryLocator] {
    map { locator in
      guard let redirected = (redirects.first {
        $0.isMatching(locator)
      }) else {
        return locator
      }
      
      return EntryLocator(url: redirected.url, since: locator.since, guid: locator.guid, title:  locator.title)
    }
  }
}
