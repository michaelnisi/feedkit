//
//  queue.swift
//  FeedKit
//
//  Created by Michael Nisi on 30.06.17.
//  Copyright © 2017 Michael Nisi. All rights reserved.
//

import Foundation

// TODO: Update queue after redirects
// TODO: Make sure to log if a guid couldn’t be found

struct Queue<Item: Hashable> {
  private var itemsByGUIDs = [Int : Item]()
  
  private var fwd = [Int]()
  private var bwd = [Int]()
  
  public init() {}
  
  public init(items: [Item], next guid: String? = nil) throws {
    assert(!items.isEmpty)
    
    try add(items: items)
    
    guard let i = guid?.hashValue else {
      return
    }
 
    var found: Int
    repeat {
      found = forward()!.hashValue
    } while found != i
    
    let _ = backward() // forward() to get item with next guid
  }
  
  private mutating func castling(a: inout [Int], b: inout [Int]) -> Item? {
    guard !a.isEmpty else {
      return nil
    }
    
    let key = a.removeFirst()
    let entry = itemsByGUIDs[key]!
    
    b.append(key)
    
    return entry
  }
  
  public mutating func forward() -> Item? {
    return castling(a: &fwd, b: &bwd)
  }
  
  public mutating func backward() -> Item? {
    return castling(a: &bwd, b: &fwd)
  }
  
  public func contains(_ item: Item) -> Bool {
    return itemsByGUIDs.contains { $0.key == item.hashValue }
  }
  
  public mutating func add(_ item: Item) throws {
    guard !contains(item) else {
      throw QueueError.alreadyInQueue
    }
    
    let key = item.hashValue
    
    itemsByGUIDs[key] = item
    fwd.append(key)
  }
  
  public mutating func add(items: [Item]) throws {
    try items.forEach { item in
      try add(item)
    }
  }
  
  public mutating func remove(_ item: Item) throws {
    let key = item.hashValue
    
    guard itemsByGUIDs.removeValue(forKey: key) != nil else {
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
  
  public func add(entry: Entry) throws {
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
