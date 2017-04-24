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
// TODO: Provide latest entry in user
// TODO: Make sure to log if a guid couldn’t be found

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
        url: "https://daringfireball.net/thetalkshow/rss",
        guid: "82fb2da2ac4bca88a68e8913ae12cb7346268bed"
      ),
      EntryLocator(
        url: "http://feeds.wnyc.org/newyorkerradiohour",
        guid: "d603394f7083968191d8d2660871f9e80535e4fd"
      ),
      EntryLocator(
        url: "http://feeds.gimletmedia.com/hearreplyall",
        guid: "0282d828ba6c02cb5dda7bbb89a6558f22b4531d"
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
