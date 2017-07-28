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

/// A generic queue holding minimal state.
public struct Queue<Item: Hashable> {
  
  private var itemsByHashValues = [Int : Item]()
  
  public func enumerated() -> EnumeratedSequence<Dictionary<Int, Item>> {
    return itemsByHashValues.enumerated()
  }
  
  private var fwd = [Int]()
  private var bwd = [Int]()
  
  public mutating func add(_ item: Item) throws {
    guard !contains(item) else {
      throw QueueError.alreadyInQueue
    }
    
    let key = item.hashValue
    
    itemsByHashValues[key] = item
    fwd.append(key)
  }
  
  public mutating func add(items: [Item]) throws {
    try items.reversed().forEach { item in
      try add(item)
    }
  }
  
  public init() {}
  
  // TODO: throw
  public init(items: [Item]) {
    try! add(items: items)
  }
  
  @discardableResult private mutating func castling(a: inout [Int], b: inout [Int]) -> Item? {
    guard !a.isEmpty else {
      return nil
    }
    
    let key = a.removeLast()
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
  
  public mutating func skip(to item: Item) throws {
    guard contains(item) else {
      throw QueueError.notInQueue
    }
    
    if fwd.contains(item.hashValue) {
      while forward() != item {}
    } else {
      while backward() != item {}
    }
  }
  
  var now: Item? { get {
    guard let hashValue = bwd.last else {
      return nil
    }
    return itemsByHashValues[hashValue]
  }}
  
  var nextUp: [Item] { get {
    return fwd.reversed().flatMap { itemsByHashValues[$0.hashValue] }
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
    } else {
      let index = bwd.index(of: key)
      bwd.remove(at: index!)
    }
  }
}
