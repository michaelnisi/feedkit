//
//  feeds.swift - all about feeds
//  FeedKit
//
//  Created by Michael Nisi on 17.07.14.
//  Copyright (c) 2014 Michael Nisi. All rights reserved.
//

import Foundation

public func == (lhs: Feed, rhs: Feed) -> Bool {
  return
    lhs.author == rhs.author &&
    lhs.image == rhs.image &&
    lhs.language == rhs.language &&
    lhs.link == rhs.link &&
    lhs.summary == rhs.summary &&
    lhs.title == rhs.title &&
    lhs.updated == rhs.updated
}

public struct Feed: Equatable, Printable {
  public let author: String?
  public let image: String?
  public let language: String?
  public let link: String?
  public let summary: String?
  public let title: String
  public let updated: Double?
  public let url: String

  public lazy var date: NSDate
    = NSDate(timeIntervalSince1970: self.updated!)

  public var description: String {
    return "Feed: \(title) @ \(url)"
  }

  public init (title: String, url: String) {
    self.title = title
    self.url = url
  }

  public init (
    author: String?
  , image: String?
  , language: String?
  , link: String?
  , summary: String?
  , title: String
  , updated: Double?
  , url: String) {
    self.author = author
    self.image = image
    self.language = language
    self.link = link
    self.summary = summary
    self.title = title
    self.updated = updated
    self.url = url
  }
}

func error (userInfo: NSDictionary) -> NSError {
  return NSError(
    domain: "FeedKit.feeds"
  , code: 1
  , userInfo: userInfo
  )
}

public class FeedRepository {
  let queue: dispatch_queue_t
  let svc: MangerHTTPService

  public init (queue: dispatch_queue_t, svc: MangerHTTPService) {
    self.queue = queue
    self.svc = svc
  }

  public func feeds (urls: [String], cb: ((NSError?, [Feed]?) -> Void)) {
    let manger = svc
    dispatch_async(self.queue, {
      manger.feeds(urls) { (er, dicts) in
        if er != nil {
          cb(er, nil)
        } else if dicts != nil {
          cb(nil, feedsFrom(dicts! as [[String:AnyObject]]))
        } else {
          cb(error(["noFeeds":true]), nil)
        }
      }
    })
  }
}



