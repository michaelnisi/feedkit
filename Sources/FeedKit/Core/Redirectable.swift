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
    return items.filter { $0.isRedirected }
  }
  
  var isRedirected: Bool {
    guard let o = originalURL else {
      return false
    }
    return o != url
  }
  
}

