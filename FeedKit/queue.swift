//
//  queue.swift
//  FeedKit
//
//  Created by Michael Nisi on 30.06.17.
//  Copyright © 2017 Michael Nisi. All rights reserved.
//

import Foundation

public enum QueueError: Error {
  case alreadyInQueue(Int)
  case notInQueue
}

/// A generic queue holding minimal state.
public struct Queue<Item: Hashable> {
  
  private var itemsByHashValues = [Int : Item]()
  
  // TODO: Replace with Sequence
  
  /// Returns an unsorted sequence of the items in the queue.
  public func enumerated() -> EnumeratedSequence<Dictionary<Int, Item>> {
    return itemsByHashValues.enumerated()
  }
  
  private var now: Int?
  private var fwd = [Int]()
  private var bwd = [Int]()
  
  /// Adds one item to the queue.
  ///
  /// - Throws: Will throw `QueueError.alreadyInQueue` if the item is already 
  /// in the queue, because this is probably a programming error.
  public mutating func add(_ item: Item) throws {
    guard !contains(item) else {
      throw QueueError.alreadyInQueue(item.hashValue)
    }
    
    let key = item.hashValue
    itemsByHashValues[key] = item
    fwd.append(key)
  }
  
  public var isEmpty: Bool { get { return itemsByHashValues.isEmpty } }
  
  /// Add multiple items to the queue at once, in reverse order, so that the 
  /// order of `items` becomes the order of the queue.
  public mutating func add(items: [Item]) throws {
    let shouldSetNow = isEmpty && !items.isEmpty
    try items.reversed().forEach { item in
      try add(item)
    }
    if shouldSetNow {
      now = fwd.removeLast().hashValue
    }
  }
  
  public init() {}
  
  /// Creates a new queue populated with `items` with its first item as 
  /// `current`.
  ///
  /// - Parameter items: The items to enqueue, an empty array is OK.
  public init(items: [Item]) {
    try! add(items: items)
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
  
  public mutating func forward() -> Item? {
    return castling(a: &fwd, b: &bwd)
  }
  
  public mutating func backward() -> Item? {
    return castling(a: &bwd, b: &fwd)
  }
  
  public mutating func skip(to item: Item) throws {
    guard contains(item) else {
      throw QueueError.notInQueue
    }
  
    var it: Item?
    if fwd.contains(item.hashValue) {
      repeat {
        it = forward()
      } while it != item && it != nil
    } else {
      repeat {
        it = backward()
      } while it != item && it != nil
    }
  }
  
  var current: Item? { get {
    guard let hashValue = now else {
      return nil
    }
    return itemsByHashValues[hashValue]
  }}
  
  var nextUp: [Item] { get {
    return fwd.reversed().flatMap {
      guard $0.hashValue != now else {
        return nil
      }
      return itemsByHashValues[$0.hashValue]
    }
  }}
  
  public func contains(_ item: Item) -> Bool {
    return itemsByHashValues.keys.contains(item.hashValue)
  }

  public mutating func remove(_ item: Item) throws {
    let key = item.hashValue
    
    guard itemsByHashValues.removeValue(forKey: key) != nil else {
      throw QueueError.notInQueue
    }
    
    if let index = fwd.index(of: key) {
      fwd.remove(at: index)
    } else if let index = bwd.index(of: key) {
      bwd.remove(at: index)
    }
  }
}

