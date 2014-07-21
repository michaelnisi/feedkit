//
//  transform.swift
//  FeedKit
//
//  Created by Michael Nisi on 25.09.14.
//  Copyright (c) 2014 Michael Nisi. All rights reserved.
//

import Foundation

public func double (dict: NSDictionary, key: String) -> Double? {
  return dict[key] as? Double
}

public func str (dict: NSDictionary, key: String) -> String? {
  return dict[key] as? String
}

public func updated (dict: NSDictionary) -> Double? {
  var updated = 0.0
  if let seconds = double(dict, "updated") {
    updated = seconds / 1000
  }
  return updated
}

public func feedFrom (dict: NSDictionary) -> Feed? {
  let title = str(dict, "title")
  let url = str(dict, "feed")
  let valid = (title != nil && url != nil)
  if !valid {
    return nil
  }
  return Feed(
    author: str(dict, "author")
  , image: str(dict, "image")
  , language: str(dict, "language")
  , link: str(dict, "link")
  , summary: str(dict, "summary")
  , title: title!
  , updated: updated(dict)
  , url: url!
  )
}

public func feedsFrom (dicts: [NSDictionary]) -> [Feed] {
  var feeds = [Feed]()
  for dict: NSDictionary in dicts {
    if let feed = feedFrom(dict) {
      feeds.append(feed)
    }
  }
  return feeds
}
