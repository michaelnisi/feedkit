//
//  http.swift
//  FeedKit
//
//  Created by Michael Nisi on 17.07.14.
//  Copyright (c) 2014 Michael Nisi. All rights reserved.
//

import Foundation

enum Callback<NSError, T> {
  case Error(() -> NSError)
  case Response(() -> T)
}

struct MangerClientOpts {
  let feedsURL: String
}

struct MangerClient {
  let feedsURL: String
  let conf: NSURLSessionConfiguration
  let sess: NSURLSession
  
  init (opts: MangerClientOpts) {
    conf = NSURLSessionConfiguration.defaultSessionConfiguration()
    sess = NSURLSession(configuration: conf)
    feedsURL = opts.feedsURL
  }
  
  func parse (data: NSData) -> AnyObject? {
    return NSJSONSerialization.JSONObjectWithData(
      data
      , options: NSJSONReadingOptions(0)
      , error: nil)
  }
  
  func json (urls: Array<String>) -> NSData {
    return NSJSONSerialization.dataWithJSONObject(
      urls.map({
        url -> Dictionary<String, String> in
        ["url": url]
        })
      , options: NSJSONWritingOptions(0)
      , error: nil)
  }
  
  func req (urls: [String]) -> NSMutableURLRequest {
    let url = NSURL(string: feedsURL)
    let req = NSMutableURLRequest(URL: url)
    req.HTTPMethod = "POST"
    req.HTTPBody = json(urls)
    return req
  }
  
  func error (code: Int, reason: String, res: NSURLResponse, data: NSData?)
    -> NSError {
      let dataString = data != nil ? NSString(data: data, encoding: 4) : "nil"
      let info = ["reason": reason, "response": res, "data": dataString]
      return NSError(domain: "Manger", code: code, userInfo: info)
  }
  
  func feeds (dicts: [NSDictionary]) -> [Feed] {
    var feeds = [Feed]()
    for dict: NSDictionary in dicts {
      if let feed = feed(dict) {
        feeds += feed
      }
    }
    return feeds
  }
  
  func feeds (urls: Array<String>, cb: (Callback<NSError, [Feed]>) -> ()) {
    let task = sess.dataTaskWithRequest(req(urls)) {
      (data, res, er) in
      if er != nil  {
        return cb(Callback.Error({er}))
      }
      let code = (res as NSHTTPURLResponse).statusCode
      func report (reason: String) -> NSError {
        return self.error(code, reason: reason, res: res, data: data)
      }
      if data != nil && code == 200 {
        if let json: AnyObject? = self.parse(data) {
          let dicts = json as [NSDictionary]
          var feeds = self.feeds(dicts)
          cb(Callback.Response({feeds}))
        } else {
          cb(Callback.Error({report("received data not JSON")}))
        }
      } else {
        cb(Callback.Error({report("no data received")}))
      }
    }
    task.resume()
  }
}
