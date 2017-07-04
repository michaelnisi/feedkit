//
//  queue.swift
//  FeedKit
//
//  Created by Michael Nisi on 30.06.17.
//  Copyright © 2017 Michael Nisi. All rights reserved.
//

import Foundation

// TODO: Update queue after redirects

public enum QueueError: Error {
  case alreadyInQueue
  case notInQueue
}

struct Queue<Item: Hashable> {
  private var itemsByHashValues = [Int : Item]()
  
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
    assert(!items.isEmpty)
    
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

public final class EntryQueue: Queueing {
  
  let browser: Browsing
  
  public init(browser: Browsing) {
    self.browser = browser
  }
  
  var locators: [EntryLocator]?
  
  /// A temporary method to enable persistance through app state preservation.
  /// Sort order of locators matters here.
  ///
  /// - Parameter locators: Sorted list of entry locators.
  public func integrate(locators: [EntryLocator]) {
    self.locators = locators
  }
  
  public func entries(
    entriesBlock: @escaping (Error?, [Entry]) -> Void,
    entriesCompletionBlock: @escaping (Error?) -> Void
    ) -> Operation {
    
    // TODO: Persist in database and wrap all this in a proper Operation
    
    guard let locators = self.locators else {
      return Operation() // NOP
    }
    
    let guids = locators.flatMap { $0.guid }
    var acc = [Entry]()
    
    let op = browser.entries(locators, entriesBlock: { error, entries in
      assert(error == nil)
      
      acc = acc + entries
    }) { error in
      assert(error == nil)
      
      DispatchQueue.global().async {
        var entriesByGUID = [String : Entry]()
        acc.forEach {
          entriesByGUID[$0.guid] = $0
        }
        let sorted = guids.flatMap { entriesByGUID[$0] }
        
        try! self.queue.add(items: sorted)
        
        DispatchQueue.main.async {
          // Obviously, we ought to use a single callback for this API.
          entriesBlock(nil, sorted)
          entriesCompletionBlock(nil)
        }
      }
    }
    
    self.locators = nil // integrating just once
    
    return op
  }
  
  private var queue = Queue<Entry>()
  
  public var delegate: QueueDelegate?
  
  private func postDidChangeNotification() {
    NotificationCenter.default.post(
      name: Notification.Name(rawValue: FeedKitQueueDidChangeNotification),
      object: self
    )
  }
  
  public func add(_ entry: Entry) throws {
    try queue.add(entry)
    
    delegate?.queue(self, added: entry)
    postDidChangeNotification()
  }
  
  public func add(entries: [Entry]) throws {
    try queue.add(items: entries)
  }
  
  public func remove(_ entry: Entry) throws {
    try queue.remove(entry)
    
    delegate?.queue(self, removedGUID: entry.guid)
    postDidChangeNotification()
  }
  
  public func contains(_ entry: Entry) -> Bool {
    return queue.contains(entry)
  }
  
  public func next() -> Entry? {
    return queue.forward()
  }
  
  public func previous() -> Entry? {
    return queue.backward()
  }
  
}
