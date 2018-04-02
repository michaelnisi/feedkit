//
//  queue.swift
//  FeedKit
//
//  Created by Michael Nisi on 30.06.17.
//  Copyright © 2017 Michael Nisi. All rights reserved.
//

import Foundation

public enum QueueError: Error {
  case alreadyInQueue
  case notInQueue
}

/// A destructive Sequence representing a queue that lets you navigate back and
/// forth within the contained items.
public struct Queue<Item: Hashable> {
  
  /// The content.
  private var itemsByHashValues = [Int : Item]()
  
  /// The key of the current item in `itemsByHashValues`.
  private var now: Int?
  
  /// The sorted keys of `itemsByHashValues`, key of last added item last.
  private var hashValues = [Int]()
  
  /// The sorted items in the queue at this moment.
  public var items: [Item] { get {
    return hashValues.map {
      itemsByHashValues[$0]!
    }
  }}
  
  /// Removes all items from the queue.
  public mutating func removeAll() {
    itemsByHashValues.removeAll()
    now = nil
    hashValues.removeAll()
  }
  
  public var isEmpty: Bool { get {
    return hashValues.isEmpty
  }}
  
  /// Prepends `item` to queue, making it its head.
  ///
  /// - Throws: Will throw `QueueError.alreadyInQueue` if the item is already 
  /// in the queue, because this is probably a programming error.
  public mutating func prepend(_ item: Item) throws -> Item {
    let h = item.hashValue
    
    guard !contains(item) else {
      throw QueueError.alreadyInQueue
    }
    
    itemsByHashValues[h] = item
    hashValues = [h] + hashValues
    
    if now == nil { now = h }
    
    return item
  }
  
  /// Prepends multiple `items` to the queue at once, in reverse order, so the
  /// order of `items` becomes the order of the head of the queue.
  ///
  /// - Returns: Returns the prepended items.
  @discardableResult public mutating func prepend(items: [Item]) -> [Item] {
    var acc = [Item]()
    for item in items.reversed() {
      do {
        acc.append(try prepend(item))
      } catch {
        // Can be inferred from the accumulated items returned.
      }
    }
    return acc
  }
  
  /// Appends `item` to queue, making it its tail.
  public mutating func append(_ item: Item) throws {
    let h = item.hashValue
    
    guard !contains(item) else {
      throw QueueError.alreadyInQueue
    }
    
    itemsByHashValues[h] = item
    hashValues.append(h)
    
    if now == nil { now = h }
  }
  
  /// Appends `items` as the tail of the queue.
  public mutating func append(items: [Item]) throws {
    var acc: Error?
    for item in items {
      do {
        try append(item)
      } catch {
        acc = error
      }
    }
    if let error = acc {
      throw error
    }
  }
  
  public init() {}
  
  /// Creates a new queue populated with `items` with its first item as 
  /// `current`.
  ///
  /// - Parameter items: The items to enqueue, an empty array is OK.
  public init(items: [Item]) {
    prepend(items: items)
    now = hashValues.first
  }
  
  private var currentIndex: Int? { get {
    guard
      let item = now,
      let i = hashValues.index(of: item) else {
      return nil
    }
    return i
  }}
  
  public mutating func forward() -> Item? {
    guard let i = currentIndex, i < hashValues.count - 1 else {
      return nil
    }
    let n = hashValues.index(after: i)
    let h = hashValues[n]
    now = h
    return itemsByHashValues[h]
  }
  
  public mutating func backward() -> Item? {
    guard let i = currentIndex, i > 0 else {
      return nil
    }
    let n = hashValues.index(before: i)
    let h = hashValues[n]
    now = h
    return itemsByHashValues[h]
  }
  
  public mutating func skip(to item: Item) throws {
    guard contains(item) else {
      throw QueueError.notInQueue
    }
    now = item.hashValue
  }
  
  public var current: Item? { get {
    guard let hashValue = now else {
      return nil
    }
    return itemsByHashValues[hashValue]
  }}
  
  public var nextUp: [Item] { get {
    guard
      let h = now,
      let i = hashValues.index(of: h),
      i != hashValues.count - 1 else {
      return []
    }
    let keys = hashValues.split(separator: h)
    guard let last = keys.last else {
      return []
    }
    return last.compactMap {
      itemsByHashValues[$0]
    }
  }}
  
  public func contains(_ item: Item) -> Bool {
    return hashValues.contains(item.hashValue)
  }
  
  mutating func removeItem(with hashValue: Int) throws {
    guard
      itemsByHashValues.removeValue(forKey: hashValue) != nil,
      let i = hashValues.index(of: hashValue) else {
      throw QueueError.notInQueue
    }
    
    hashValues.remove(at: i)
    if now == hashValue { now = nil }
  }

  public mutating func remove(_ item: Item) throws {
    try removeItem(with: item.hashValue)
  }
}

// MARK: - Equatable

extension Queue: Equatable {
  public static func ==(lhs: Queue, rhs: Queue) -> Bool {
    return lhs.items == rhs.items
  }
}

// MARK: - Sequence

extension Queue: Sequence {
  public func makeIterator() -> IndexingIterator<Array<Item>> {
    return items.makeIterator()
  }
}

// MARK: - ExpressibleByArrayLiteral

extension Queue: ExpressibleByArrayLiteral {
  public init(arrayLiteral elements: Element...) {
    self.init(items: elements)
  }
}

