//
//  cache.swift - store and retrieve data
//  FeedKit
//
//  Created by Michael Nisi on 03.11.14.
//  Copyright (c) 2014 Michael Nisi. All rights reserved.
//

import Foundation
import Skull
import os.log

struct Cache {
  static var log = OSLog(subsystem: "ink.codes.feedkit", category: "cache")
}

/// Wraps a value into an `NSObject`.
class ValueObject<T>: NSObject {
  let value: T
  init(_ value: T) {
    self.value = value
  }
}

/// Cachable objects, currently feeds and entries, must adopt this protocol,
/// which requires a globally unique resource locator (url) and a timestamp (ts).
public protocol Cachable {
  var ts: Date? { get }
  var url: FeedURL { get }
}

/// Housekeeping for local caching.
public protocol Caching {
  
  /// Flushes any dispensable resources to save memory.
  func flush() throws
  
  /// Closes any underlying database files.
  func closeDatabase()
  
}

/// Enumerate default time-to-live intervals used for caching.
///
/// - None: Zero seconds.
/// - Short: One hour.
/// - Medium: Eight hours.
/// - Long: 24 hours.
/// - Forever: Infinity.
public enum CacheTTL {
  case none
  case short
  case medium
  case long
  case forever
  
  /// The default interpretation of this time interval in seconds.
  var defaults: TimeInterval {
    switch self {
    case .none: return 0
    case .short: return 3600
    case .medium: return 28800
    case .long: return 86400
    case .forever: return Double.infinity
    }
  }
}

extension CacheTTL: CustomStringConvertible {
  
  public var description: String {
    switch self {
    case .none: return "CacheTTL.none"
    case .short: return "CacheTTL.short"
    case .medium: return "CacheTTL.medium"
    case .long: return "CacheTTL.long"
    case .forever: return "CacheTTL.forever"
    }
  }
  
}

// MARK: - DateCache

/// An in-memory date log.
class DateCache {
  
  private var dates = [String : Date]()
  
  let ttl: TimeInterval
  
  init(ttl: TimeInterval = CacheTTL.short.defaults) {
    self.ttl = ttl
  }
  
  func removeAll() {
    dates.removeAll()
  }
  
  /// Returns `true` if `key` has not been used or is stale.
  @discardableResult func update(_ key: String) -> Bool {
    if let prev = dates[key], prev.timeIntervalSinceNow < ttl {
      return false
    }
    dates[key] = Date()
    return true
  }
  
}

// MARK: - Caching

/// Abstract super class for embedded (SQLite) databases.
public class LocalCache: Caching {
  
  fileprivate let schema: String
  
  var url: URL?
  
  var _db: Skull?
  
  /// An open database connection or a crashed program.
  var db: Skull {
    get {
      guard _db != nil else {
        do {
          _db = try open()
        } catch {
          os_log("could not open database: %{public}@",
                 log: Cache.log, type: .error, error as CVarArg)
          fatalError(String(describing: error))
        }
        return _db!
      }
      return _db!
    }
  }
  
  /// Strictly submit all blocks, accessing the database, to this serial queue
  /// to serialize database access.
  let queue: DispatchQueue
  
  fileprivate func open() throws -> Skull {
    let freshDB = try Skull(url)
    let sql = try String(contentsOfFile: schema, encoding: String.Encoding.utf8)
    try freshDB.exec(sql)
    return freshDB
  }
  
  /// Initializes a newly created cache.
  ///
  /// - Parameters:
  ///   - schema: The path of the database schema file.
  ///   - url: The file URL of the database to use—and create if necessary.
  public init(schema: String, url: URL?) throws {
    let label = "ink.codes.feedkit.\(type(of: self))"
    let database = url?.debugDescription ?? "in-memory"
    
    os_log(
      """
      initializing: {
        schema: %{public}@,
        database: %{public}@,
        queue: %{public}@
      }
      """, log: Cache.log, type: .debug, schema, database, label)
    
    self.schema = schema
    self.url = url
    self.queue = DispatchQueue(label: label, attributes: [])
  }

  public func flush() throws {
    try queue.sync {
      try self._db?.flush()
    }
  }
  
  public func closeDatabase() {
    queue.sync {
      self._db = nil
    }
  }
}

// MARK: - Utilities

extension LocalCache {
  
  /// Slices an array into fixed sized arrays.
  ///
  /// - Parameters:
  ///   - elements: The array to slice.
  ///   - count: The number of elements in the returned arrays.
  ///
  /// - Returns: An array of arrays with count`.
  static func slice<T>(elements: [T], with count: Int) -> [Array<T>] {
    guard elements.count > count else {
      return [elements]
    }
    
    var i = 0
    var start = 0
    var end = 0
    var slices = [[T]]()
    
    repeat {
      start = min(count * i, elements.count)
      end = min(start + count, elements.count)
      
      let slice = elements[start..<end]
      if !slice.isEmpty {
        slices.append(Array(slice))
      }
      
      i += 1
    } while start != end
    
    return slices
  }
  
  /// Returns the median timestamp of the specified cachable items.
  ///
  /// - Parameters:
  ///   - items: The cachable items of which to locate the median.
  ///   - sorting: To skip the sorting, but lose warranty of correctness.
  ///
  /// - Returns: The median timestamp of these cachable items; or nil, if you pass
  /// an empty array.
  static func medianTS <T: Cachable> (_ items: [T], sorting: Bool = true) -> Date? {
    guard !items.isEmpty else { return nil }
    let sorted: [T]
    if sorting {
      sorted = items.sorted {
        guard $0.ts != nil else { return false }
        guard $1.ts != nil else { return true }
        return $0.ts!.compare($1.ts! as Date) == ComparisonResult.orderedDescending
      }
    } else {
      sorted = items
    }
    
    let index = sorted.count / 2
    let median = sorted[index].ts
    
    return median as Date?
  }
  
}
