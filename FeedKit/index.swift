//
//  index.swift
//  FeedKit
//
//  Created by Michael Nisi on 17.07.14.
//  Copyright (c) 2014 Michael Nisi. All rights reserved.
//

import Foundation
import Skull

let domain = "com.michaelnisi.feedkit"

typealias Transform = ([NSDictionary]) -> (NSError?, [AnyObject])

func nop (Any) -> Void {}

func wait (sema: dispatch_semaphore_t, seconds: Int = 3600 * 24) -> Bool {
  let period = Int64(CUnsignedLongLong(seconds) * NSEC_PER_SEC)
  let timeout = dispatch_time(DISPATCH_TIME_NOW, period)
  return dispatch_semaphore_wait(sema, timeout) == 0
}


func niy (domain: String = domain) -> NSError {
 let info = ["message": "not implemented yet"]
 return NSError(domain: domain, code: 1, userInfo: info)
}

public struct Image {
  let web: NSURL
  let local: NSURL?
}

public class Service: NSObject {
  let host: String
  let port: Int
  let session: NSURLSession

  func makeBaseURL () -> NSURL? {
    return nil // Override
  }
  public lazy var baseURL: NSURL = self.makeBaseURL()!

  public init (
    host: String
  , port: Int
  , session osess: NSURLSession? = nil) {
    self.host = host
    self.port = port
    if let sess = osess {
      self.session = sess
    } else {
      let conf = NSURLSessionConfiguration.defaultSessionConfiguration()
      session = NSURLSession(configuration: conf)
    }
  }
}

public class ServiceResult: Printable {
  public let request: NSURLRequest
  public let items: [AnyObject]?
  public var error: NSError?

  init (request: NSURLRequest, data: NSData) {
    self.request = request
    if let json: AnyObject = parse(data) {
      self.items = json as? [AnyObject]
    }
  }

  public var description: String {
    return "ServiceResult: \(request) \(items) \(error)"
  }

  func parse (data: NSData) -> AnyObject? {
    let (er, json: AnyObject?) = parseJSON(data)
    if let parseError = er {
      error = NSError(
        domain: domain
      , code: 1
      , userInfo: [
          "request": request.description
        , "json": parseError.description]
      )
    }
    return json
  }
}

public struct FeedQuery: Equatable, Printable {
  let url: NSURL
  let date: NSDate?

  public init (string: String) {
    self.url = NSURL(string: string)!
  }

  public init (url: NSURL) {
    self.url = url
  }

  public init (url: NSURL, date: NSDate) {
    self.url = url
    self.date = date
  }

  public var time: Int {
    return date != nil ? Int(round(date!.timeIntervalSince1970 * 1000)) : -1
  }

  public var description: String {
    return "FeedQuery: \(url) since \(date)"
  }
}

public func == (lhs: FeedQuery, rhs: FeedQuery) -> Bool {
  return lhs.url == rhs.url
}

public func == (lhs: Feed, rhs: AnyObject) -> Bool {
  if rhs is Feed {
    return lhs == rhs as Feed
  } else {
    return false
  }
}

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

public class Feed: Equatable, Printable {
  public let author: String?
  public let image: String?
  public let language: String?
  public let link: NSURL?
  public let summary: String?
  public let title: String
  public let updated: Double?
  public let url: NSURL

  public lazy var date: NSDate
    = NSDate(timeIntervalSince1970: self.updated!)

  public var description: String {
    return "Feed: \(title) @ \(url)"
  }

  init (
    author: String?
  , image: String?
  , language: String?
  , link: NSURL?
  , summary: String?
  , title: String
  , updated: Double?
  , url: NSURL) {
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

public func == (lhs: Enclosure, rhs: Enclosure) -> Bool {
  return
    lhs.href == rhs.href &&
    lhs.length == rhs.length &&
    lhs.type == rhs.type
}

public class Enclosure: Equatable, Printable {
  let href: NSURL
  let length: Int?
  let type: String

  public var description: String {
    return "Enclosure: \(href)"
  }

  public init (href: NSURL, length: Int, type: String) {
    self.href = href
    self.length = length
    self.type = type
  }
}

public func == (lhs: Entry, rhs: Entry) -> Bool {
  return
    lhs.author == rhs.author &&
    lhs.enclosure == rhs.enclosure &&
    lhs.duration == rhs.duration &&
    lhs.id == rhs.id &&
    lhs.image == rhs.image &&
    lhs.link == rhs.link &&
    lhs.subtitle == rhs.subtitle &&
    lhs.title == rhs.title &&
    lhs.updated == rhs.updated
}

public class Entry: Equatable, Printable {
  public let author: String?
  public let enclosure: Enclosure
  public let duration: Int?
  public let id: String?
  public let image: String?
  public let link: NSURL?
  public let subtitle: String?
  public let summary: String?
  public let title: String?
  public let updated: Double?

  public var description: String {
    return "Entry: \(title) @ \(enclosure.href)"
  }

  init (
    author: String?
  , enclosure: Enclosure
  , duration: Int?
  , id: String?
  , image: String?
  , link: NSURL?
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

public protocol FeedService {
  func feeds (queries: [FeedQuery], cb: (NSError?, [Feed]?) -> Void)
  func entries (queries: [FeedQuery], cb: (NSError?, [Entry]?) -> Void)
}

public protocol FeedCache {
  mutating func set (feed: Feed) -> Void
  func get (url: NSURL) -> Feed?
  mutating func reset () -> Void
}

public class MemoryFeedCache: FeedCache  {
  let cache: NSCache

  public init () {
    cache = NSCache()
  }

  public func set(feed: Feed) {
    cache.setObject(feed, forKey: feed.url)
  }

  public func get(url: NSURL) -> Feed? {
    return cache.objectForKey(url) as? Feed
  }

  public func reset() {
    cache.removeAllObjects()
  }
}

public class FeedRepository {
  let svc: FeedService
  let queue: dispatch_queue_t
  let cache: FeedCache

  public init (svc: FeedService, queue: dispatch_queue_t, cache: FeedCache) {
    self.svc = svc
    self.queue = queue
    self.cache = cache
  }

  public func feeds (urls: [NSURL], cb: (NSError?, [Feed]?) -> Void) -> Void {
    let cache = self.cache
    let svc = self.svc
    dispatch_async(queue, {
      var cached = [Feed]()
      var queries = [FeedQuery]()
      for url: NSURL in urls {
        if let feed = cache.get(url) {
          cached.append(feed)
        } else {
          let query = FeedQuery(url: url)
          queries.append(query)
        }
      }
      svc.feeds(queries) { (er, result) in
        func partly () -> [Feed]? {
          return cached.count > 0 ? cached : nil
        }
        if er != nil {
          return cb(er, partly())
        }
        if let retrieved = result {
          let feeds = cached + retrieved
          cb(nil, feeds)
        } else {
          let info = ["message": "unexpected service error"]
          let er = NSError(domain: domain, code: 1, userInfo: info)
          cb(er, partly())
        }
      }
    })
  }

  public func feed (url: NSURL, cb: (NSError?, Feed?) -> Void) -> Void {
    feeds([url]) { (er, feeds) in
      cb(er, feeds?.first)
    }
  }
}

public class EntryRepository {
  public func recent (feeds: [Feed], cb: (NSError?, [Entry]?) -> Void) -> Void {

  }

  public func entries (feed: Feed, cb: (NSError?, [Entry]?) -> Void) -> Void {

  }

  public func entry (url: NSURL, cb: (NSError?, Entry?) -> Void) -> Void {

  }

  public func update (queries: [FeedQuery], cb: (NSError?, [Entry]?) -> Void) -> Void {

  }
}
