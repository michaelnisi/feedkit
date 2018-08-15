//
//  Queued.swift
//  FeedKit
//
//  Created by Michael Nisi on 07.05.18.
//  Copyright © 2018 Michael Nisi. All rights reserved.
//

import Foundation

/// An item that can be in the user’s queue. At the moment these are entries,
/// exclusively, but we might add seasons, etc.
public enum Queued {
  case temporary(EntryLocator, Date, ITunesItem?)
  case pinned(EntryLocator, Date, ITunesItem?)
  case previous(EntryLocator, Date)
  
  /// Creates a temporarily queued `entry` including `iTunes` item.
  init(entry locator: EntryLocator, iTunes: ITunesItem? = nil) {
    self = .temporary(locator, Date(), iTunes)
  }
}

extension Queued: Equatable {
  static public func ==(lhs: Queued, rhs: Queued) -> Bool {
    return lhs.hashValue == rhs.hashValue
  }
}

extension Queued: CustomStringConvertible {
  public var description: String {
    switch self {
    case .temporary(_, _, _):
      return "Queued.temporary"
    case .pinned(_, _, _):
      return "Queued.pinned"
    case .previous(_, _):
      return "Queued.previous"
    }
  }
}

extension Queued: CustomDebugStringConvertible {
  public var debugDescription: String {
    switch self {
    case .temporary(let loc, let ts, let iTunes):
      return """
      Queued.temporary {
      locator: \(loc),
      ts: \(ts),
      iTunes: \(String(describing: iTunes))
      }
      """
    case .pinned(let loc, let ts, let iTunes):
      return """
      Queued.pinned {
      locator: \(loc),
      ts: \(ts),
      iTunes: \(String(describing: iTunes))
      }
      """
    case .previous(let loc, let ts):
      return """
      Queued.previous {
      locator: \(loc),
      ts: \(ts)
      }
      """
    }
  }
}

extension Queued: Hashable {

  private static func makeHash(
    marker: String, locator: EntryLocator, timestamp: Date
    ) -> Int {
    // Using timestamp’s hash value directly, doesn’t yield expected results.
    let ts = Int(timestamp.timeIntervalSince1970)
    return marker.hashValue ^ locator.hashValue ^ ts
  }
  
  public var hashValue: Int {
    switch self {
    case .temporary(let loc, let ts, _),
         .pinned(let loc, let ts, _),
         .previous(let loc, let ts):
      return Queued.makeHash(marker: description, locator: loc, timestamp: ts)
    }
  }
  
}

extension Queued {
  public var entryLocator: EntryLocator {
    switch self {
    case .temporary(let loc, _, _),
         .pinned(let loc, _, _),
         .previous(let loc, _):
      return loc
    }
  }
}

extension Queued {
  
  /// Returns a copy leaving off iTunes metadata.
  public func dropITunes() -> Queued {
    switch self {
    case .temporary(let loc, let ts, _):
      return .temporary(loc, ts, nil)
    case .pinned(let loc, let ts, _):
      return .pinned(loc, ts, nil)
    case .previous:
      return self
    }
  }
  
}
