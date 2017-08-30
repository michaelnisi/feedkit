//
//  queue.swift
//  FeedKit
//
//  Created by Michael Nisi on 30.06.17.
//  Copyright © 2017 Michael Nisi. All rights reserved.
//

import Foundation

// TODO: Add Queue protocol

public enum QueueError: Error {
  case alreadyInQueue(Int)
  case notInQueue
}

/// A destructive Sequence representing a queue, in which lets you navigate
/// back and forth within the contained items.
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
  
  public var isEmpty: Bool { get {
    return hashValues.isEmpty
  }}
  
  /// Adds one item to the queue.
  ///
  /// - Throws: Will throw `QueueError.alreadyInQueue` if the item is already 
  /// in the queue, because this is probably a programming error.
  public mutating func prepend(_ item: Item) throws {
    let h = item.hashValue
    
    guard !contains(item) else {
      throw QueueError.alreadyInQueue(h)
    }
    
    itemsByHashValues[h] = item
    hashValues = [h] + hashValues
    
    if now == nil { now = h }
  }
  
  /// Add multiple items to the queue at once, in reverse order, so that the 
  /// order of `items` becomes the order of the queue.
  public mutating func prepend(items: [Item]) throws {
    for item in items {
      try prepend(item)
    }
  }
  
  public mutating func append(_ item: Item) throws {
    let h = item.hashValue
    
    guard !contains(item) else {
      throw QueueError.alreadyInQueue(h)
    }
    
    itemsByHashValues[h] = item
    hashValues.append(h)
    
    if now == nil { now = h }
  }
  
  public mutating func append(items: [Item]) throws {
    for item in items {
      try append(item)
    }
  }
  
  public init() {}
  
  /// Creates a new queue populated with `items` with its first item as 
  /// `current`.
  ///
  /// - Parameter items: The items to enqueue, an empty array is OK.
  public init(items: [Item]) {
    try! prepend(items: items)
    now = hashValues.first
  }
  
  @discardableResult private mutating func castling(
    a: inout [Int], b: inout [Int]) -> Item? {
    
    guard a.count > 1 else {
      return nil
    }
    
    let key = a.removeLast()
    let item = itemsByHashValues[key]!
    
    b.append(now!)
    now = item.hashValue
    
    return item
  }
  
  var currentIndex: Int? { get {
    guard
      let item = now,
      let i = hashValues.index(of: item) else {
      return nil
    }
    return i
  }}
  
  public mutating func forward() -> Item? {
    guard let i = currentIndex, i < hashValues.count else {
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
  
  var current: Item? { get {
    guard let hashValue = now else {
      return nil
    }
    return itemsByHashValues[hashValue]
  }}
  
  var nextUp: [Item] { get {
    guard let h = now else {
      return []
    }
    let keys = hashValues.split(separator: h)
    guard keys.count > 1, let last = keys.last else {
      return []
    }
    return last.flatMap {
      itemsByHashValues[$0]
    }
  }}
  
  public func contains(_ item: Item) -> Bool {
    return hashValues.contains(item.hashValue)
  }

  public mutating func remove(_ item: Item) throws {
    let h = item.hashValue
    
    guard
      itemsByHashValues.removeValue(forKey: h) != nil,
      let i = hashValues.index(of: h) else {
      throw QueueError.notInQueue
    }
    
    hashValues.remove(at: i)
    if now == h { now = nil }
  }
}

extension Queue: Sequence {
  public func makeIterator() -> IndexingIterator<Array<Item>> {
    return items.makeIterator()
  }
}

