//
//  FeedKit.swift
//  FeedKit
//
//  Created by Michael Nisi on 17.07.14.
//  Copyright (c) 2014 Michael Nisi. All rights reserved.
//

import Foundation

public protocol FeedService {
  func entries (queries: [FeedQuery], cb:((NSError?, ServiceResult?) -> Void))
  func feeds (queries: [FeedQuery], cb: ((NSError?, ServiceResult?) -> Void))
}

public protocol SearchService {
  func search (query: String, cb: ((NSError?, ServiceResult?) -> Void))
  func suggest (term: String, cb: ((NSError?, ServiceResult?) -> Void))
}

func notyet () -> NSError {
  return NSError(domain: "FeedKit", code: 1, userInfo: ["message": "not implemented yet"])
}

func parseJSON (data: NSData) -> (NSError?, AnyObject?) {
  var er: NSError?
  if let json: AnyObject = NSJSONSerialization.JSONObjectWithData(
    data
  , options: NSJSONReadingOptions.AllowFragments
  , error: &er) {
    return (er, json)
  }
  return (NSError(
    domain: "FeedKit.io"
  , code: 1
  , userInfo: ["message":"couldn't create JSON object"])
  , nil)
}

public class Service {
  let host: String
  let port: Int

  class func defaultSessionConfiguration () -> NSURLSessionConfiguration {
    return NSURLSessionConfiguration.defaultSessionConfiguration()
  }
  lazy var sess = NSURLSession(
    configuration: Service.defaultSessionConfiguration()
  )

  func makeBaseURL () -> NSURL? {
    return nil // Override
  }
  public lazy var baseURL: NSURL = self.makeBaseURL()!

  init (host: String, port: Int) {
    self.host = host
    self.port = port
  }
}

public class ServiceResult {
  public let request: NSURLRequest
  public let items: [AnyObject]?
  public var error: NSError?

  init (request: NSURLRequest, data: NSData) {
    self.request = request
    if let json: AnyObject = parse(data) {
      self.items = json as? [AnyObject]
    }
  }

  func parse (data: NSData) -> AnyObject? {
    let (er, json: AnyObject?) = parseJSON(data)
    if let parseError = er {
      error = NSError(
        domain: "FeedKit.manger"
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
    self.url = NSURL(string: string)
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

public class FeedRepository {
  let queue: dispatch_queue_t
  let svc: FeedService

  public init (queue: dispatch_queue_t, svc: FeedService) {
    self.queue = queue
    self.svc = svc
  }

  func error (userInfo: NSDictionary) -> NSError {
    return NSError(
      domain: "FeedKit.FeedRepository"
    , code: 1
    , userInfo: userInfo
    )
  }
  
  public func feed (url: NSURL, cb: (NSError?, Feed?) -> Void) -> Void {
    
  }
  
  public func feeds (
    queries: [FeedQuery]
  , cb: ((NSError?, [Feed]?) -> Void)) {
    let manger = svc
    let error = self.error
    dispatch_async(self.queue, {
      manger.feeds(queries) { (er, result) in
        if let ioError = er {
          cb(ioError, nil)
        } else if let res = result {
          if let jsonError = res.error {
            cb(jsonError, nil)
          } else if let dicts = res.items {
            let (error, feeds) = feedsFrom(dicts as [NSDictionary])
            cb(er, feeds)
          } else {
            let er = error([
              "message": "result has no dictionaries",
              "noFeeds": true
            ])
            cb(er, nil)
          }
        } else {
          let er = error(["message":"oh snap! no result"])
          cb(er, nil)
        }
      }
    })
  }
}

public class ITunesStore {
  public func searchFeed (term: String) -> Void {
    
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

public class EntryRepository {
  let queue: dispatch_queue_t
  let svc: FeedService

  init (queue: dispatch_queue_t, svc: FeedService) {
    self.queue = queue
    self.svc = svc
  }

  func error (userInfo: NSDictionary) -> NSError {
    return NSError(
      domain: "FeedKit.entries"
      , code: 1
      , userInfo: userInfo
    )
  }

  public func entries (
    queries: [FeedQuery]
    , cb: ((NSError?, [Entry]?) -> Void)) {
      let manger = svc
      let error = self.error
      dispatch_async(self.queue, {
        manger.entries(queries) { (er, result) in
          if let ioError = er {
            cb(ioError, nil)
          } else if let res = result {
            if let jsonError = res.error {
              cb(jsonError, nil)
            } else if let dicts = res.items {
              let (error, entries) = entriesFrom(dicts as [NSDictionary])
              cb(error, entries)
            } else {
              let er = error([
                "message": "result has no items"
              , "noItems": true
              ])
              cb(er, nil)
            }
          } else {
            let er = error(["message": "oh snap! no result"])
            cb(er, nil)
          }
        }
      })
  }
}
