//
//  ITunesItem.swift
//  FeedKit
//
//  Created by Michael Nisi on 05.02.18.
//  Copyright © 2018 Michael Nisi. All rights reserved.
//

import Foundation

// Additional per podcast information, aquired via iTunes search, entirely
// optional. Especially `iTunesID` is not used within this framework, which is
// identifying feeds by URLs.
public struct ITunesItem: Codable {
  
  /// Identifies this item and associates it with a feed.
  public let url: FeedURL
  
  // iTunes metadata
  
  public let iTunesID: Int
  public let img100: String
  public let img30: String
  public let img60: String
  public let img600: String
  
  /// Initializes a new iTunes item.
  ///
  /// - Parameters:
  ///   - url: The URL of the associated feed.
  ///   - iTunesID: The iTunes store lookup identifier.
  ///   - img100: URL of a prescaled image representing this feed.
  ///   - img30: URL of a prescaled image representing this feed.
  ///   - img60: URL of a prescaled image representing this feed.
  ///   - img600: URL of a prescaled image representing this feed.
  public init(
    url: FeedURL,
    iTunesID: Int,
    img100: String,
    img30: String,
    img60: String,
    img600: String
  ) {
    self.url = url
    self.iTunesID = iTunesID
    self.img100 = img100
    self.img30 = img30
    self.img60 = img60
    self.img600 = img600
  }
  
}

extension ITunesItem: CustomStringConvertible {
  
  public var description: String {
    return "ITunesItem: { \(iTunesID) }"
  }
}

extension ITunesItem: CustomDebugStringConvertible {
  
  public var debugDescription: String {
    return """
    ITunesItem: {
      url: \(url),
      iTunesID: \(iTunesID),
      img100: \(img100),
      img30: \(img30),
      img60: \(img60),
      img600: \(img600)
    }
    """
  }
}

extension ITunesItem: Equatable, Hashable {
  
  public static func ==(lhs: ITunesItem, rhs: ITunesItem) -> Bool {
    return lhs.url == rhs.url && lhs.iTunesID == rhs.iTunesID
  }
  
  
  public func hash(into hasher: inout Hasher) {
    hasher.combine(url)
    hasher.combine(iTunesID)
  }
}
