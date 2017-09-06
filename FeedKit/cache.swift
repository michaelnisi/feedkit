//
//  cache.swift - store and retrieve data
//  FeedKit
//
//  Created by Michael Nisi on 03.11.14.
//  Copyright (c) 2014 Michael Nisi. All rights reserved.
//

import Foundation
import Skull

// MARK: - SQLite Database Super Class

/// Abstract super class for embedded (SQLite) databases.
public class LocalCache {
  
  fileprivate let schema: String
  
  var url: URL?
  
  let db: Skull
  
  /// Strictly submit to this serial queue to serialize database (write)-access.
  let queue: DispatchQueue
  
  let sqlFormatter: SQLFormatter
  
  fileprivate func open() throws {
    var er: Error?
    
    let db = self.db
    let schema = self.schema
    
    queue.sync {
      do {
        let sql = try String(contentsOfFile: schema, encoding: String.Encoding.utf8)
        try db.exec(sql)
      } catch {
        er = error
      }
    }
    
    if let error = er {
      throw error
    }
  }
  
  /// Initializes a newly created cache.
  ///
  /// - Parameters:
  ///   - schema: The path of the database schema file.
  ///   - url: The file URL of the database to use—and create if necessary.
  public init(schema: String, url: URL?) throws {
    self.schema = schema
    self.url = url
    
    // Comment-in to remove all database files at start-up.
//    if let p = url { try FileManager.default.removeItem(at: p) }
    
    self.db = try Skull(url)
    
    let me = type(of: self)
    self.queue = DispatchQueue(label: "ink.codes.\(me)", attributes: [])
    
    self.sqlFormatter = SQLFormatter()
    
    try open()
  }
  
  fileprivate func close() throws {
    try db.close()
  }
  
  deinit {
    try! db.close()
  }
  
  public func flush() throws {
    try db.flush()
  }
}

// MARK: - Utilities

extension LocalCache {
  
  // TODO: Move slice utitlity function into LocalCache super class
  
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
  
  /// Returns `true` if the specified timestamp is older than the specified time
  /// to live.
  ///
  /// - Parameters:
  ///   - ts: The timestamp to check if it's older than the specified ttl.
  ///   - ttl: The maximal age to allow.
  ///
  /// - Returns: `true` if the timestamp is older than the maximal age.
  static func stale(_ ts: Date, ttl: TimeInterval) -> Bool {
    return ts.timeIntervalSinceNow + ttl < 0
  }
  
  /// Returns the median timestamp of the specified cachable items.
  ///
  /// - Parameters:
  ///   - items: The cachable items of which to locate the median.
  ///   - sorting: To skip the sorting but lose warranty of correctness.
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
