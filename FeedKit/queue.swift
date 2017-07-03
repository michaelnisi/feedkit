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

struct Queue<Item: Identifiable> {
  private var itemsByGUIDs = [String : Item]()
  
  private var fwd = [String]()
  private var bwd = [String]()
  
  public init() {}
  
  public init(items: [Item], next guid: String? = nil) throws {
    assert(!items.isEmpty)
    
    try add(items: items)
    
    guard let i = guid else {
      return
    }
 
    var found: String
    repeat {
      found = forward()!.guid
    } while found != i
    
    let _ = backward() // forward() to get item with next guid
  }
  
  private mutating func castling(a: inout [String], b: inout [String]) -> Item? {
    guard !a.isEmpty else {
      return nil
    }
    
    let guid = a.removeFirst()
    let entry = itemsByGUIDs[guid]!
    
    b.append(guid)
    
    return entry
  }
  
  public mutating func forward() -> Item? {
    return castling(a: &fwd, b: &bwd)
  }
  
  public mutating func backward() -> Item? {
    return castling(a: &bwd, b: &fwd)
  }
  
  public func contains(guid: String) -> Bool {
    return itemsByGUIDs.contains { $0.key == guid }
  }
  
  public mutating func add(_ item: Item) throws {
    let guid = item.guid
    guard !contains(guid: guid) else {
      throw QueueError.alreadyInQueue
    }
    itemsByGUIDs[guid] = item
    fwd.append(guid)
  }
  
  public mutating func add(items: [Item]) throws {
    try items.forEach { item in
      try add(item)
    }
  }
  
  public mutating func remove(guid: String) throws {
    guard itemsByGUIDs.removeValue(forKey: guid) != nil else {
      throw QueueError.notInQueue
    }
    
    if let index = fwd.index(of: guid) {
      fwd.remove(at: index)
    } else {
      let index = bwd.index(of: guid)
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
  
  public func remove(guid: String) throws {
    try queue.remove(guid: guid)
    
    delegate?.queue(self, removedGUID: guid)
    postDidChangeNotification()
  }
  
  public func contains(guid: String) -> Bool {
    return queue.contains(guid: guid)
  }
  
  public func next() -> Entry? {
    return queue.forward()
  }
  
  public func previous() -> Entry? {
    return queue.backward()
  }
  
}
