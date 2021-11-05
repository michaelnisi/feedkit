//===----------------------------------------------------------------------===//
//
// This source file is part of the FeedKit open source project
//
// Copyright (c) 2021 Michael Nisi and collaborators
// Licensed under MIT License
//
// See https://github.com/michaelnisi/feedkit/blob/main/LICENSE for license information
//
//===----------------------------------------------------------------------===//

import Foundation

/// Receives stuff from dependencies.
public protocol Receiving {}

public extension Receiving where Self: Operation {
  func findFeed() -> Feed? {
    guard let p = dependencies.first(where: { $0 is ProdvidingFeeds })
      as? ProdvidingFeeds else {
        return nil
    }

    return p.feeds.first
  }

  func findEntries() -> Set<Entry> {
    guard let p = dependencies.first(where: { $0 is ProvidingEntries })
      as? ProvidingEntries else {
        return Set()
    }

    return p.entries
  }

  func findError() -> Error? {
    guard let p = dependencies.first(where: { $0 is Providing })
      as? Providing else {
        return nil
    }

    return p.error
  }
}
