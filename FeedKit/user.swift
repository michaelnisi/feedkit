//
//  user.swift
//  FeedKit
//
//  Created by Michael Nisi on 31/01/16.
//  Copyright © 2016 Michael Nisi. All rights reserved.
//

import Foundation

// TODO: Persist locators

class UserEvents: UIDocument {
  
}

public class User: Queueing {  
  private let browser: Browsing
  
  public func entries(
    entriesBlock: (ErrorType?, [Entry]) -> Void,
    entriesCompletionBlock: (ErrorType?) -> Void
  ) -> NSOperation {
    
    let locators = [
      EntryLocator(
        url: "http://rss.acast.com/anotherround",
        guid: "ee535b0aace2c176982a7166cf08e659"
      ),
      EntryLocator(
        url: "http://daringfireball.net/thetalkshow/rss",
        guid: "d99ae604b5233b5072d4411153b28736"
      ),
      EntryLocator(
        url: "http://feeds.metaebene.me/cre/m4a",
        guid: "90c6f7ec8226c2dc1190bf1509f9b8f8"
      ),
      EntryLocator(
        url: "http://nightvale.libsyn.com/rss",
        guid: "b2136edf27854dd9e698107b7b1dcc2f"
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
  public func push(entry: Entry) throws {
    throw FeedKitError.NIY
  }
  
  /// Remove specified entry from the queue and dispatch a notification.
  ///
  /// - Parameter entry: The entry to remove from the queue.
  /// - Throws: Throws if the provided entry is not in the queue.
  public func pop(entry: Entry) throws {
    throw FeedKitError.NIY
  }
}
