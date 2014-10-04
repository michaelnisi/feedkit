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

func req (url: NSURL, queries: [FeedQuery]) -> NSMutableURLRequest {
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
    return (NSError(
      domain: "FeedKit.manger"
    , code: 1
    , userInfo: ["message":"missing fields (title or feed) in \(dict)"]
    ), nil)
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

func stringFrom (errors: [NSError]) -> String {
  var str: String = errors.count > 0 ? "" : "no errors"
  for error in errors {
    str += "\(error.description)\n"
  }
  return str
}

func feedsFrom (dicts: [NSDictionary]) -> (NSError?, [Feed]) {
  var error: NSError?
  var feeds = [Feed]()
  var errors = [NSError]()
  for dict: NSDictionary in dicts {
    let (er, feed) = feedFrom(dict)
    if er != nil { errors.append(er!) }
    if feed != nil { feeds.append(feed!) }
  }
  if errors.count > 0 {
    error = NSError(
      domain: "FeedKit.manger"
    , code: 1
    , userInfo: ["message":stringFrom(errors)]
    )
  }
  return (error, feeds)
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
    return (NSError(
      domain: "FeedKit.manger"
    , code: 1
    , userInfo: ["message": "missing fields (url, length, or type) in \(dict)"])
    , nil)
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
    return (NSError(
      domain: "FeedKit.manger"
    , code: 1
    , userInfo: ["message": "missing fields (title or enclosure) in \(dict)"])
    , nil)
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

func entriesFrom (dicts: [NSDictionary]) -> (NSError?, [Entry]) {
  var error: NSError?
  var errors = [NSError]()
  var entries = [Entry]()
  for dict: NSDictionary in dicts {
    let (er, entry) = entryFrom(dict)
    if er != nil { errors.append(er!) }
    if entry != nil { entries.append(entry!) }
  }
  if errors.count > 0 {
    error = NSError(
      domain: "FeedKit.manger"
    , code: 1
    , userInfo: ["message": stringFrom(errors)]
    )
  }
  return (error, entries)
}

public class MangerService: Service, FeedService {
  func spawn (
    queries: [FeedQuery]
  , path: String
  , cb: ((NSError?, ServiceResult?) -> Void)) {
    let url = NSURL(string: path, relativeToURL: baseURL)
    let sess = self.sess
    let request = req(url, queries)
    let task = sess.dataTaskWithRequest(request) { (data, res, er) in
      if (er != nil) {
        return cb(er!, nil)
      }
      let code = (res as NSHTTPURLResponse).statusCode
      if code == 200 && data != nil {
        cb(nil, ServiceResult(request: request, data:data))
      } else {
        let dataString = data != nil
          ? NSString(data: data!, encoding: 4)
          : "nil"
        let info = [
          "message": "no data received"
        , "response": res
        , "data": dataString]
        let er = NSError(domain: "FeedKit.manger", code: code, userInfo: info)
        cb(er, nil)
      }
    }
    task.resume()
  }

  func queryError (queries: [FeedQuery]) -> NSError? {
    if queries.count == 0 {
      return NSError(
        domain: "FeedKit.manger"
      , code: 1
      , userInfo: ["message":"no queries"])
    } else {
      return nil
    }
  }

  public func entries (
    queries: [FeedQuery]
  , cb:((NSError?, ServiceResult?) -> Void)) {
    if let er = queryError(queries) {
      return cb(er, nil)
    }
    spawn(queries, path: "entries", cb: cb)
  }

  public func feeds (
    queries: [FeedQuery]
  , cb: ((NSError?, ServiceResult?) -> Void)) {
    if let er = queryError(queries) {
      return cb(er, nil)
    }
    spawn(queries, path: "feeds", cb: cb)
  }
}

public class MangerHTTPService: MangerService {
  override func makeBaseURL() -> NSURL? {
    return NSURL(string: "http://" + self.host + ":" + String(self.port))
  }
}
