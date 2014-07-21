//
//  io.swift
//  FeedKit
//
//  Created by Michael Nisi on 22.07.14.
//  Copyright (c) 2014 Michael Nisi. All rights reserved.
//

import Foundation

public func parse (data: NSData) -> AnyObject? {
  return NSJSONSerialization.JSONObjectWithData(
    data
    , options: nil
    , error: nil)
}

func error (code: Int, reason: String, res: NSURLResponse, data: NSData?) -> NSError {
  let dataString = data != nil ? NSString(data: data!, encoding: 4) : "nil"
  let info = ["reason": reason, "response": res, "data": dataString]
  return NSError(domain: "Manger", code: code, userInfo: info)
}

public func == (lhs: Query, rhs: Query) -> Bool {
  return lhs.url == rhs.url
}

public struct Query: Equatable {
  let url: String
  let date: NSDate?
  
  public init (_ url: String) {
    self.url = url
  }
  
  public init (_ url: String, date: NSDate) {
    self.url = url
    self.date = date
  }
  
  public var time: Double {
    return round(date!.timeIntervalSince1970 * 1000)
  }
}

public func payload (queries: [Query]) -> NSData {
  return NSJSONSerialization.dataWithJSONObject(
    queries.map { q -> [String:AnyObject] in
      if (q.date != nil) {
        return ["url": q.url, "since": Int(q.time)]
      } else {
        return ["url": q.url]
      }
    }
    , options: NSJSONWritingOptions(0)
    , error: nil
  )!
}

func queries (urls: [String]) -> [Query] {
  return urls.map { url -> Query in Query(url) }
}

public func req (url: NSURL, queries: [Query]) -> NSMutableURLRequest {
  let req = NSMutableURLRequest(URL: url)
  req.HTTPMethod = "POST"
  req.HTTPBody = payload(queries)
  return req
}

public class MangerService {
  let host: String
  let port: Int
  
  class func defaultSessionConfiguration () -> NSURLSessionConfiguration {
    return NSURLSessionConfiguration.defaultSessionConfiguration()
  }
  lazy var sess = NSURLSession(configuration: MangerHTTPService.defaultSessionConfiguration())

  public lazy var baseURL: NSURL = self.makeBaseURL()!
  func makeBaseURL () -> NSURL? {
    return nil
  }
  
  public init (host: String, port: Int) {
    self.host = host
    self.port = port
  }
  
  func spawn (queries: [Query], path: String, cb: ((NSError?, [NSDictionary]?) -> Void)) {
    let url = NSURL(string: path, relativeToURL: baseURL)
    let sess = self.sess
    let task = sess.dataTaskWithRequest(req(url, queries)) {
      (data, res, er) in
      if (er != nil) {
        return cb(er!, nil)
      }
      let code = (res as NSHTTPURLResponse).statusCode
      func report (reason: String) -> NSError {
        return error(code, reason, res, data)
      }
      if data != nil && code == 200 {
        if let json: AnyObject = parse(data) {
          cb(nil, json as? [NSDictionary])
        } else {
          cb(report("received data not JSON"), nil)
        }
      } else {
        cb(report("no data received"), nil)
      }
    }
    task.resume()

  }
  
  public func entries (urls: [String], cb:((NSError?, [NSDictionary]?) -> Void)) {
    entries(queries(urls), cb: cb)
  }
  func entries (queries: [Query], cb:((NSError?, [NSDictionary]?) -> Void)) {
    spawn(queries, path: "entries", cb: cb)
  }
  
  public func feeds (urls: [String], cb: ((NSError?, [NSDictionary]?) -> Void)) {
    feeds(queries(urls), cb: cb)
  }
  func feeds (queries: [Query], cb: ((NSError?, [NSDictionary]?) -> Void)) {
    spawn(queries, path: "feeds", cb: cb)
  }
}

public class MangerHTTPService: MangerService {
  override func makeBaseURL() -> NSURL? {
    return NSURL(string: "http://" + self.host + ":" + String(self.port))
  }
}
