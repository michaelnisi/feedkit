//
//  fanboy.swift
//  FeedKit
//
//  Created by Michael Nisi on 08.10.14.
//  Copyright (c) 2014 Michael Nisi. All rights reserved.
//

import Foundation

func queryURL (baseURL: NSURL, verb: String, query: String) -> NSURL? {
  return NSURL(string: "\(verb)?q=\(query)", relativeToURL: baseURL)
}

func searchResultFrom (dict: NSDictionary) -> (NSError?, SearchResult?) {
  let author = dict["author"] as? String
  let feed = urlFrom (dict, "feed")
  let valid = author != nil && feed != nil
  if !valid {
    let info = ["message": "missing fields (author or feed) in \(dict)"]
    let er = NSError(domain: domain, code: 1, userInfo: info)
    return (er, nil)
  }
  return (nil, SearchResult(author: author!, cat: .Store, feed: feed!))
}

func searchResultsFrom (dicts: [NSDictionary]) -> (NSError?, [SearchResult]?) {
  if dicts.count < 1 {
    return (nil, nil)
  }
  var er: NSError?
  var results = [SearchResult]()
  var errors = [NSError]()
  for dict: NSDictionary in dicts {
    let (er, result) = searchResultFrom(dict)
    if er != nil { errors.append(er!) }
    if result != nil { results.append(result!) }
  }
  if errors.count > 0 {
    let info = ["message": stringFrom(errors)]
    er = NSError(domain: domain, code: 1, userInfo: info)
  }
  return (er, results)
}

func suggestionsFrom (terms: [String]) -> (NSError?, [Suggestion]?) {
  if terms.count < 1 {
    return (nil, nil)
  }
  let suggestions = terms.map { (term) -> Suggestion in
    return Suggestion(cat: .Store, term: term)
  }
  return (nil, suggestions)
  // Returning tuples to be consistent with the other transform functions.
}

enum FanboyPath: String {
  case Search = "search"
  case Suggest = "suggest"
}

public class FanboyService: NSObject {
  let baseURL: NSURL
  let queue: NSOperationQueue

  lazy var conf: NSURLSessionConfiguration = {
    let c = NSURLSessionConfiguration.defaultSessionConfiguration()
    // TODO: Configure
    return c
  }()

  lazy var session: NSURLSession = {
    return NSURLSession(
      configuration: self.conf
    , delegate: self
    , delegateQueue: self.queue
    )
  }()

  typealias Handler = (NSError?, NSData?, Bool) -> Void
  var handlers = [NSURLSessionTask:Handler]()

  public init (host: String, port: Int, queue: NSOperationQueue) {
    self.baseURL = NSURL(string: "http://\(host):\(port)")!
    self.queue = queue
  }

  private func requestWithPath (
    path: FanboyPath
  , term: String) -> NSURLRequest? {
    if let url = queryURL(baseURL, path.rawValue, term) {
      return NSURLRequest(URL: url)
    }
    return nil
  }
}

extension FanboyService: SearchService {
  public func suggest (
    term: String
  , cb: (NSError?, [Suggestion]?) -> Void)
  -> NSURLSessionDataTask? {
    if let req = requestWithPath(.Suggest, term: term) {
      var acc: NSMutableData?
      func handler (error: NSError?, data: NSData?, done: Bool) -> Void {
        if let er = error {
          return cb(er, nil)
        }
        if done {
          let (error, json: AnyObject?) = parseJSON(acc!)
          if let er = error {
            return cb(er, nil)
          }
          if let terms = json as? [String] {
            let (error, suggestions) = suggestionsFrom(terms)
            if let er = error {
              return cb(er, nil)
            }
            if let sugs = suggestions {
              return cb(nil, sugs)
            }
          }
          // If we reach this, we assume there are no suggestions.
          return cb(nil, nil)
        }
        if let buf = data {
          if acc == nil {
            acc = NSMutableData(capacity: buf.length)
          }
          acc?.appendData(buf)
        }
      }
      let task = session.dataTaskWithRequest(req)
      handlers[task] = handler
      task.resume()
      return task
    } else {
      let er = NSError(
        domain: domain
      , code: 0
      , userInfo: ["message": "couldn't create request"]
      )
      cb(er, nil)
      return nil
    }
  }
}

extension FanboyService: NSURLSessionTaskDelegate {
  public func URLSession(
    session: NSURLSession
  , task: NSURLSessionTask
  , didCompleteWithError error: NSError?) {
    if let cb = handlers[task] {
      cb(error, nil, true)
      handlers[task] = nil
    } else {
      // TODO: Remove
      assert(false)
    }
  }
}

extension FanboyService: NSURLSessionDataDelegate {
  public func URLSession(
    session: NSURLSession
  , dataTask: NSURLSessionDataTask
  , didReceiveData data: NSData) {
    if dataTask.state == .Running {
      if let cb = handlers[dataTask] {
        cb(nil, data, false)
      } else {
        // TODO: Remove
        assert(false)
      }
    }
  }
}
