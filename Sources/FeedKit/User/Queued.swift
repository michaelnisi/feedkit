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

/// An item that can be in the user’s queue. At the moment these are entries,
/// exclusively, but we might add other types like seasons, etc.
public enum Queued {
  
  /// Temporary items are allowed to be removed.
  case temporary(EntryLocator, Date, ITunesItem?)
  
  /// Pinned items must only be removed by users.
  case pinned(EntryLocator, Date, ITunesItem?)
  
  /// Previous items are for tracking history.
  case previous(EntryLocator, Date)
  
  /// Creates a temporarily queued `entry` including optional `iTunes` item.
  init(entry locator: EntryLocator, iTunes: ITunesItem? = nil) {
    self = .temporary(locator, Date(), iTunes)
  }
}

extension Queued {
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
      Queued.temporary (
        locator: \(loc),
        ts: \(ts),
        iTunes: \(String(describing: iTunes))
      )
      """
    case .pinned(let loc, let ts, let iTunes):
      return """
      Queued.pinned (
        locator: \(loc),
        ts: \(ts),
        iTunes: \(String(describing: iTunes))
      )
      """
    case .previous(let loc, let ts):
      return """
      Queued.previous (
        locator: \(loc),
        ts: \(ts)
      )
      """
    }
  }
}

extension Queued: Hashable {

  /// Combines case and locator, ignoring timestamps and iTunes items.
  public func hash(into hasher: inout Hasher) {
    switch self {
    case .temporary(let loc, _, _):
      hasher.combine(0)
      hasher.combine(loc)
    case .pinned(let loc, _, _):
      hasher.combine(1)
      hasher.combine(loc)
    case .previous(let loc, _):
      hasher.combine(2)
      hasher.combine(loc)
    }
  }
  
}

extension Queued {

  /// Locates the entry of this queued item.
  public var entryLocator: EntryLocator {
    switch self {
    case .temporary(let loc, _, _),
         .pinned(let loc, _, _),
         .previous(let loc, _):
      return loc
    }
  }

  /// The identifier of a unique entry if the locator provides one.
  public var guid: String? {
    return entryLocator.guid
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
