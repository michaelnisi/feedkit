//
//  Providing.swift
//  FeedKit
//
//  Created by Michael Nisi on 19.01.18.
//  Copyright © 2018 Michael Nisi. All rights reserved.
//

import Foundation
import Ola

/// Providing protocols are implemented by operations to provide results to
/// another operation while being its dependency.
protocol Providing {
  var error: Error? { get }
}

protocol ProvidingReachability: Providing {
  var status: OlaStatus { get }
}

protocol ProvidingLocators: Providing {
  var locators: [EntryLocator]  { get }
}

protocol ProvidingEntries: Providing {
  var entries: Set<Entry> { get }
}

protocol ProdvidingFeeds: Providing {
  var feeds: Set<Feed> { get }
}

extension FeedKitOperation {
  
  func findLocators() throws -> [EntryLocator] {
    var found = Set<EntryLocator>()
    for dep in dependencies {
      if case let req as ProvidingLocators = dep {
        guard req.error == nil else {
          throw req.error!
        }
        found.formUnion(req.locators)
      }
    }
    return Array(found)
  }
  
}
