//
//  FeedKitError.swift
//  FeedKit
//
//  Created by Michael Nisi on 05.02.18.
//  Copyright © 2018 Michael Nisi. All rights reserved.
//

import Foundation

public let cacheURL = Bundle.module.url(forResource: "cache", withExtension: "sql")!
public let userURL = Bundle.module.url(forResource: "user", withExtension: "sql")!

/// Enumerate all error types possibly thrown within the FeedKit framework.
public enum FeedKitError: Error {
  case unknown
  case niy
  case notAString
  case general(message: String)
  case cancelledByUser
  case notAFeed
  case notAnEntry
  case serviceUnavailable(Error?)
  case feedNotCached(urls: [String])
  case unknownEnclosureType(type: String)
  case multiple(errors: [Error])
  case unexpectedJSON
  case sqlFormatting
  case cacheFailure(error: Error)
  case invalidSearchTerm(term: String)
  case invalidEntry(reason: String)
  case invalidEntryLocator(reason: String)
  case invalidEnclosure(reason: String)
  case invalidFeed(reason: String)
  case invalidSuggestion(reason: String)
  case offline
  case noForceApplied
  case missingEntries(locators: [EntryLocator])
  case unexpectedDatabaseRow
  case unidentifiedFeed
}

extension FeedKitError: CustomStringConvertible {
  public var description: String {
    switch self {
    case .unknown:
      return "unkown error"
    case .niy:
      return "not implemented yet"
    case .notAString:
      return "not a string"
    case .general(let message):
      return "general error: \(message)"
    case .cancelledByUser:
      return "cancelled by user"
    case .notAFeed:
      return "not a feed"
    case .notAnEntry:
      return "not an entry"
    case .serviceUnavailable(let er):
      return "service unavailable: \(String(describing: er))"
    case .feedNotCached(let urls):
      return "feed not cached: \(urls)"
    case .unknownEnclosureType(let type):
      return "unknown enclosure type: \(type)"
    case .multiple(let errors):
      return "multiple errors: \(String(describing: errors))"
    case .unexpectedJSON:
      return "unexpected JSON"
    case .sqlFormatting:
      return "SQL formatting error"
    case .cacheFailure(let er):
      return "cache failure: \(String(describing: er))"
    case .invalidSearchTerm(let term):
      return "invalid search term: \(term)"
    case .invalidEntry(let reason):
      return "invalid entry: \(reason)"
    case .invalidEntryLocator(let reason):
      return "invalid entry locator: \(reason)"
    case .invalidEnclosure(let reason):
      return "invalid enclosure: \(reason)"
    case .invalidFeed(let reason):
      return "invalid feed: \(reason)"
    case .invalidSuggestion(let reason):
      return "invalid suggestion: \(reason)"
    case .offline:
      return "offline"
    case .noForceApplied:
      return "no force applied"
    case .missingEntries(let locators):
      return "missing entries: \(locators)"
    case .unexpectedDatabaseRow:
      return "unexpected database row"
    case .unidentifiedFeed:
      return "unidentified feed"
    }
  }
}
