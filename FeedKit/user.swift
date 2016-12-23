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
        url: "http://rss.acast.com/anotherround",
        guid: "ee535b0aace2c176982a7166cf08e659"
      ),
      EntryLocator(
        url: "http://daringfireball.net/thetalkshow/rss",
        guid: "d99ae604b5233b5072d4411153b28736"
      ),
      EntryLocator(
        url: "https://feeds.metaebene.me/cre/m4a",
        guid: "0289b89e6d29d2cb70d76686efb58cc5"
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
