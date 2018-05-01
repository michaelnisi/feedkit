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
protocol Providing {
  var error: Error? { get }
}

protocol ProvidingReachability: Providing {
  var status: OlaStatus { get }
}

protocol ProvidingFeedURLs: Providing {
  var urls: [FeedURL]  { get }
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

// This grows into a global access hub. Operation dependencies are terribly
// opaque. I think, I don’t like this pattern.

enum ProvidingError: Error {
  case missingStatus, missingLocators
}

protocol FeedURLsDependent {}

extension FeedURLsDependent where Self: Operation {
  
  func findFeedURLs() throws -> [FeedURL] {
    for dep in dependencies {
      if case let prov as ProvidingLocators = dep {
        guard prov.error == nil else {
          throw prov.error!
        }
        return prov.locators.map { $0.url }
      }
    }
    throw ProvidingError.missingLocators
  }
  
}

// MARK: - ReachabilityDependent

protocol ReachabilityDependent {}

extension ReachabilityDependent where Self: Operation {
  
  /// Finds and returns the first reachability status in operation dependencies,
  /// which implement `ProvidingReachability`.
  ///
  /// - Returns: The first `OlaStatus` found.
  /// - Throws: `ProvidingError.missingStatus` if status hasn’t been provided.
  func findStatus() throws -> OlaStatus {
    var status: OlaStatus?
    for dep in dependencies {
      if case let prov as ProvidingReachability = dep {
        guard prov.error == nil else {
          throw prov.error!
        }
        switch prov.status {
        case .cellular, .reachable:
          // Reachable is assumed, so these aren’t relevant.
          continue
        case .unknown:
          status = prov.status
        }
      }
    }
    guard let found = status else {
      throw ProvidingError.missingStatus
    }
    return found
  }
  
}

// MARK: - LocatorsDependent

protocol LocatorsDependent {}

extension LocatorsDependent where Self: Operation {
  
  /// Returns locators of the **first** locator providing dependency. Note that
  /// these are not accumulated from all providers, but only from the first one.
  ///
  /// - Throws: If no dependency provides locators, this throws
  /// `ProvidingError.missingLocators`.
  func findLocators() throws -> [EntryLocator] {
    for dep in dependencies {
      if case let prov as ProvidingLocators = dep {
        guard prov.error == nil else {
          throw prov.error!
        }
        return prov.locators
      }
    }
    throw ProvidingError.missingLocators
  }
  
}
