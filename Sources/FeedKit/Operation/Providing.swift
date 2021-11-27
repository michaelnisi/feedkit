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
import Ola
import os.log

/// Providing protocols are implemented by operations to provide results to
/// another operation while being its dependency.
public protocol Providing {
  var error: Error? { get }
}

protocol ProvidingReachability: Providing {
  var status: OlaStatus { get }
}

protocol ProvidingFeedURLs: Providing {
  var urls: [FeedURL]  { get }
}

public protocol ProvidingLocators: Providing {
  var locators: [EntryLocator]  { get }
}

public protocol ProvidingEntries: Providing {
  var entries: Set<Entry> { get }
}

public protocol ProdvidingFeeds: Providing {
  var feeds: Set<Feed> { get }
}

enum ProvidingError: Error {
  case missingStatus, missingLocators
}

