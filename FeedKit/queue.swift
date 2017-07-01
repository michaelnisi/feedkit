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

/// The queue is kept generic for easier testing.
struct Queue {
  private var itemsByGUIDs = [String : Identifiable]()
  
  private var fwd = [String]()
  private var bwd = [String]()
  
  /// Returns next entry and moves index forward.
  public mutating func forward() -> Identifiable? {
    guard !fwd.isEmpty else {
      return nil
    }
    
    let guid = fwd.removeLast()
    let entry = itemsByGUIDs[guid]!
    
    bwd.append(guid)
    
    return entry
  }
  
  public mutating func backward() -> Identifiable? {
    guard !bwd.isEmpty else {
      return nil
    }
    
    let guid = bwd.removeLast()
    let entry = itemsByGUIDs[guid]!
    
    fwd.append(guid)
    
    return entry
  }
  
  public func contains(guid: String) -> Bool {
    return itemsByGUIDs.contains { $0.key == guid }
  }
  
  public mutating func add(_ item: Identifiable) throws {
    let guid = item.guid
    guard !contains(guid: guid) else {
      throw QueueError.alreadyInQueue
    }
    itemsByGUIDs[guid] = item
    fwd.append(guid)
  }
  
  public mutating func add(items: [Identifiable]) throws {
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
  
  private var queue = Queue()
  
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
    return queue.forward() as? Entry
  }
  
  public func previous() -> Entry? {
    return queue.backward() as? Entry
  }
  
}
