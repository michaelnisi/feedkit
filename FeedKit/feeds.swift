//
//  feeds.swift
//  FeedKit
//
//  Created by Michael Nisi on 17.07.14.
//  Copyright (c) 2014 Michael Nisi. All rights reserved.
//

import Foundation

func == (lhs: Feed, rhs: Feed) -> Bool {
  return
    lhs.author == rhs.author &&
    lhs.image == rhs.image &&
    lhs.language == rhs.language &&
    lhs.link == rhs.link &&
    lhs.summary == rhs.summary &&
    lhs.title == rhs.title &&
    lhs.updated == rhs.updated
}

struct Feed: Equatable, Printable {
  let author: String
  let image: String
  let language: String
  let link: String
  let summary: String
  let title: String
  let updated: String
  
  var description: String {
    return "Feed: \(title)"
  }
}

func feed (dict: NSDictionary) -> Feed? {
  func str (key: String) -> String? {
    return dict.objectForKey(key) as? String
  }
  if let author = str("author") {
    if let image = str("image") {
      if let language = str("language") {
        if let link = str("link") {
          if let summary = str("summary") {
            if let title = str("title") {
              if let updated = str("updated") {
                return Feed(
                  author: author
                , image: image
                , language: language
                , link: link
                , summary: summary
                , title: title
                , updated: updated
                )
              }
            }
          }
        }
      }
    }
  }
  return nil
}
