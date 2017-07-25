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

struct Queue<Item: Hashable> {
  
  private var itemsByHashValues = [Int : Item]()
  
  public func enumerated() -> EnumeratedSequence<Dictionary<Int, Item>> {
    return itemsByHashValues.enumerated()
  }
  
  private var fwd = [Int]()
  private var bwd = [Int]()
  
  public init() {}
  
  /// Returns a new queue, populated with `items`, while the next `forward()` 
  /// will return the item at `index` if specified.
  ///
  /// - Parameters:
  ///   - items: An items to add to the queue, in this order.
  ///   - next: The index, in items, of the next item in queue.
  /// 
  /// - Throws: Might throw `QueueError` if internal state is inconsistent.
  public init(items: [Item], next index: Int? = nil) throws {
//    assert(!items.isEmpty)
    
    try add(items: items)
    
    guard let nextIndex = index,
      nextIndex < items.count else {
      return
    }
    
    let nextItem = items[nextIndex - 1]
    
    while forward() != nextItem {}
  }
  
  private mutating func castling(a: inout [Int], b: inout [Int]) -> Item? {
    guard !a.isEmpty else {
      return nil
    }
    
    let key = a.removeFirst()
    let item = itemsByHashValues[key]!
    
    b.append(key)
    
    return item
  }
  
  public mutating func forward() -> Item? {
    return castling(a: &fwd, b: &bwd)
  }
  
  public mutating func backward() -> Item? {
    return castling(a: &bwd, b: &fwd)
  }
  
  public func contains(_ item: Item) -> Bool {
    return itemsByHashValues.contains { $0.key == item.hashValue }
  }
  
  public mutating func add(_ item: Item) throws {
    guard !contains(item) else {
      throw QueueError.alreadyInQueue
    }
    
    let key = item.hashValue
    
    itemsByHashValues[key] = item
    fwd.append(key)
  }
  
  public mutating func add(items: [Item]) throws {
    try items.forEach { item in
      try add(item)
    }
  }
  
  public mutating func remove(_ item: Item) throws {
    let key = item.hashValue
    
    guard itemsByHashValues.removeValue(forKey: key) != nil else {
      throw QueueError.notInQueue
    }
    
    if let index = fwd.index(of: key) {
      fwd.remove(at: index)
    } else {
      let index = bwd.index(of: key)
      bwd.remove(at: index!)
    }
  }
}
