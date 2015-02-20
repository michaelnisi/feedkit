//
//  manger.swift
//  FeedKit
//
//  Created by Michael Nisi on 22.07.14.
//  Copyright (c) 2014 Michael Nisi. All rights reserved.
//

import Foundation

func payload (queries: [FeedQuery]) -> (NSError?, NSData?) {
  var er: NSError?
  var data: NSData? = NSJSONSerialization.dataWithJSONObject(
    queries.map { q -> NSDictionary in
      let url = q.url.absoluteString!
      if q.time > 0 {
        return ["url": url, "since": q.time]
      } else {
        return ["url": url]
      }
    }
    , options: NSJSONWritingOptions(0)
    , error: &er
  )
  return (er, data)
}

func req (url: NSURL, queries: [FeedQuery]) -> NSMutableURLRequest? {
  let req = NSMutableURLRequest(URL: url)
  req.HTTPMethod = "POST"
  let (er, data) = payload(queries)
  req.HTTPBody = data!
  return req
}

func updated (dict: NSDictionary) -> Double? {
  var updated = 0.0
  if let seconds = dict["updated"] as? Double {
    updated = seconds / 1000
  }
  return updated
}

func urlFrom (dict: NSDictionary, key: String) -> NSURL? {
  if let url = dict[key] as? String {
    return NSURL(string: url)
  }
  return nil
}

func feedFrom (dict: NSDictionary) -> (NSError?, Feed?) {
  let title = dict["title"] as? String
  let url = urlFrom (dict, "feed")
  let valid = title != nil && url != nil
  if !valid {
    let info = ["message": "missing fields (title or feed) in \(dict)"]
    let er = NSError(domain: domain, code: 1, userInfo: info)
    return (er, nil)
  }
  return (nil, Feed(
    author: dict["author"] as? String
  , image: dict["image"] as? String
  , language: dict["language"] as? String
  , link: urlFrom(dict, "link")
  , summary: dict["summary"] as? String
  , title: title!
  , updated: updated(dict)
  , url: url!
  ))
}

func feedsFrom (dicts: [NSDictionary]) -> (NSError?, [AnyObject]) {
  var er: NSError?
  var feeds = [Feed]()
  var errors = [NSError]()
  for dict: NSDictionary in dicts {
    let (er, feed) = feedFrom(dict)
    if er != nil { errors.append(er!) }
    if feed != nil { feeds.append(feed!) }
  }
  if errors.count > 0 {
    let info = ["message": messageFromErrors(errors)]
    er = NSError(domain: domain, code: 1, userInfo: info)
  }
  return (er, feeds)
}

func enclosureFrom (dict: NSDictionary) -> (NSError?, Enclosure?) {
  let href = urlFrom(dict, "url")
  // Manger provides length as String (e.g., "19758110")
  var length: Int?
  if let lengthStr = dict["length"] as? String {
    length = lengthStr.toInt()!
  } else {
    length = -1
  }
  let type = dict["type"] as? String
  let valid = href != nil && type != nil && length > 0
  if !valid {
    let info = ["message": "missing fields (url, length, or type) in \(dict)"]
    let er = NSError(domain: domain, code: 1, userInfo: info)
    return (er, nil)
  } else {
    return (nil, Enclosure(
      href: href!
    , length: length!
    , type: type!)
    )
  }
}

func entryFrom (dict: NSDictionary) -> (NSError?, Entry?) {
  let title = dict["title"] as? String
  var enclosure: Enclosure?
  if let enclosureDict = dict["enclosure"] as? NSDictionary {
    let (er, enc) = enclosureFrom(enclosureDict)
    enclosure = enc
  }
  let valid = title != nil && enclosure != nil
  if !valid {
    let info = ["message": "missing fields (title or enclosure) in \(dict)"]
    let er = NSError(domain: domain, code: 1, userInfo: info)
    return (er, nil)
  }
  return (nil, Entry(
    author: dict["author"] as? String
  , enclosure: enclosure!
  , duration : dict["duration"] as? Int
  , id: dict["id"] as? String
  , image: dict["image"] as? String
  , link: urlFrom(dict, "link")
  , subtitle: dict["subtitle"] as? String
  , summary: dict["summary"] as? String
  , title: title!
  , updated: updated(dict)
  ))
}

func entriesFrom (dicts: [NSDictionary]) -> (NSError?, [AnyObject]) {
  var er: NSError?
  var errors = [NSError]()
  var entries = [Entry]()
  for dict: NSDictionary in dicts {
    let (er, entry) = entryFrom(dict)
    if er != nil { errors.append(er!) }
    if entry != nil { entries.append(entry!) }
  }
  if errors.count > 0 {
    let info = ["message": messageFromErrors(errors)]
    er = NSError(domain: domain, code: 1, userInfo: info)
  }
  return (er, entries)
}

enum MangerPath: String {
  case Feeds = "feeds"
  case Entries = "entries"
}

public class MangerService: Service, FeedService {
  public func feeds (queries: [FeedQuery], cb: (NSError?, [Feed]?) -> Void) {
    cb(niy(), nil)
  }

  public func entries (queries: [FeedQuery], cb: (NSError?, [Entry]?) -> Void) {
    cb(niy(), nil)
  }
}

public class MangerHTTPService: MangerService {
  override func makeBaseURL() -> NSURL? {
    return NSURL(string: "http://" + self.host + ":" + String(self.port))
  }
}
