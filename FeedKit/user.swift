//
//  user.swift
//  FeedKit
//
//  Created by Michael Nisi on 31/01/16.
//  Copyright © 2016 Michael Nisi. All rights reserved.
//

import Foundation

// TODO: Persist locators

// TODO: Provide latest entry in user

class UserEvents: UIDocument {
  
}

open class User: Queueing {  
  fileprivate let browser: Browsing
  
  open func entries(
    _ entriesBlock: @escaping (Error?, [Entry]) -> Void,
    entriesCompletionBlock: @escaping (Error?) -> Void
  ) -> Operation {
    
    let locators = [
      EntryLocator(
        url: "http://daringfireball.net/thetalkshow/rss",
        guid: "7a87d59176a5564a86773410f90525eba60eaa32"
      )
    ]
    return browser.entries(
      locators,
      force: false,
      entriesBlock: entriesBlock,
      entriesCompletionBlock: entriesCompletionBlock
    )
  }

  public init(browser: Browsing) {
    self.browser = browser
  }
  
  // TODO: Implement pushing and popping of entries
  
  /// Add the specified entry to the end of the queue and dispatch a notification.
  /// 
  /// - Parameter entry: The entry to add to the queue.
  /// - Throws: Throws if the provided entry is already in the queue.
  open func push(_ entry: Entry) throws {
    throw FeedKitError.niy
  }
  
  /// Remove specified entry from the queue and dispatch a notification.
  ///
  /// - Parameter entry: The entry to remove from the queue.
  /// - Throws: Throws if the provided entry is not in the queue.
  open func pop(_ entry: Entry) throws {
    throw FeedKitError.niy
  }
}
