//
//  user.swift
//  FeedKit
//
//  Created by Michael Nisi on 31/01/16.
//  Copyright © 2016 Michael Nisi. All rights reserved.
//

import Foundation

// TODO: Persist locators
// TODO: Update queue after redirects
// TODO: Make sure to log if a guid couldn’t be found
// TODO: Break up User into Queue, Library, Settings, etc.

public final class User: Queueing {
  public var queueDelegate: QueueDelegate?

  fileprivate let browser: Browsing
  
  public var index: Int = 0 {
    willSet {
      guard newValue <= locators.count else {
        fatalError("out of bounds")
      }
    }
    didSet {
      guard oldValue != index else {
        return
      }
      postDidChangeNotification()
    }
  }
  
  public var count: Int { get {
    return locators.count
  }}
  
  private var locators: [EntryLocator]
  
  public func entries(
    _ entriesBlock: @escaping (Error?, [Entry]) -> Void,
    entriesCompletionBlock: @escaping (Error?) -> Void
  ) -> Operation {
    return browser.entries(
      locators,
      force: false,
      entriesBlock: entriesBlock,
      entriesCompletionBlock: entriesCompletionBlock
    )
  }
  
  private var guids: [String?] { get {
    return locators.map { $0.guid }
  }}
  
  private func index(of entry: Entry) -> Int? {
    return guids.index { $0 == entry.guid }
  }
  
  public func contains(entry: Entry) -> Bool {
    return guids.contains { $0 == entry.guid }
  }
  
  private func postDidChangeNotification() {
    NotificationCenter.default.post(
      name: Notification.Name(rawValue: FeedKitQueueDidChangeNotification),
      object: self
    )
  }
  
  @discardableResult public func remove(entry: Entry) -> Bool {
    guard contains(entry: entry) else {
      return false
    }
    
    guard let i = index(of: entry) else {
      return false
    }
    
    locators.remove(at: i)
    
    queueDelegate?.queue(self, removed: entry)
    postDidChangeNotification()
    
    return true
  }
  
  public func next(to entry: Entry) -> EntryLocator? {
    guard let i = index(of: entry) else {
      return nil
    }
    
    let n = locators.index(after: i)
    
    guard n < locators.count else {
      return nil
    }

    return locators[n]
  }
  
  public func previous(to entry: Entry) -> EntryLocator? {
    guard let i = index(of: entry) else {
      return nil
    }
    
    let n = locators.index(before: i)
    
    guard n < 0 else {
      return nil
    }
    
    return locators[n]
  }
  
  public func add(locators: [EntryLocator]) throws {
    let doublets = locators.filter {
      self.locators.contains($0)
    }
    
    guard doublets.isEmpty else {
      throw FeedKitError.alreadyInQueue
    }
    
    self.locators = locators + self.locators
  }
  
  public func add(entry: Entry) throws {
    try add(locators: [EntryLocator(entry: entry)])
    queueDelegate?.queue(self, enqueued: entry)
    postDidChangeNotification()
  }
  
  public init(browser: Browsing, locators: [EntryLocator] = [EntryLocator]()) {
    self.browser = browser
    self.locators = locators
  }
}
