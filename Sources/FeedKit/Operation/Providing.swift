//
//  Providing.swift
//  FeedKit
//
//  Created by Michael Nisi on 19.01.18.
//  Copyright © 2018 Michael Nisi. All rights reserved.
//

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

