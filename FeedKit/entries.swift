//
//  entries.swift
//  FeedKit
//
//  Created by Michael Nisi on 21.07.14.
//  Copyright (c) 2014 Michael Nisi. All rights reserved.
//

import Foundation

public func == (lhs: Enclosure, rhs: Enclosure) -> Bool {
  return lhs.href == rhs.href && lhs.length == rhs.length && lhs.type == rhs.type
}

public struct Enclosure: Equatable {
  let href: String?
  let length: Double?
  let type: String?
  
  public init (href: String?, length: Double?, type: String?) {
    self.href = href
    self.length = length
    self.type = type
  }
}

public func == (lhs: Entry, rhs: Entry) -> Bool {
  return lhs.title == rhs.title && lhs.enclosure == rhs.enclosure
}

public struct Entry: Equatable {
  public let author: String?
  public let enclosure: Enclosure
  public let duration: String?
  public let id: String?
  public let image: String?
  public let link: String?
  public let subtitle: String?
  public let summary: String?
  public let title: String?
  public let updated: Double?
  
  public var description: String {
    return "Entry: \(title) @ \(self.enclosure.href)"
  }
  
  public init (title: String, enclosure: Enclosure) {
    self.title = title
    self.enclosure = enclosure
  }
  
  public init (
      author: String?
    , enclosure: Enclosure
    , duration: String?
    , id: String?
    , image: String?
    , link: String?
    , subtitle: String?
    , summary: String?
    , title: String?
    , updated: Double?) {
      self.author = author
      self.enclosure = enclosure
      self.duration = duration
      self.id = id
      self.image = image
      self.link = link
      self.subtitle = subtitle
      self.summary = summary
      self.title = title
      self.updated = updated
  }
}

