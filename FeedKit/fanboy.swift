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
    return Suggestion(cat: .Store, term: term, ts: nil)
  }
  return (nil, suggestions)
}

public class FanboyService: NSObject {
  let baseURL: NSURL
  let conf: NSURLSessionConfiguration

  typealias Handler = (NSError?, NSData?, Bool) -> Void
  var handlers = [NSURLSessionTask:Handler]()

  var _session: NSURLSession?
  var session: NSURLSession {
    get {
      if _session == nil {
        _session = NSURLSession(
          configuration: self.conf
        , delegate: self
        , delegateQueue: nil
        )
      }
      return _session!
    }
  }

  public init (baseURL: NSURL, conf: NSURLSessionConfiguration) {
    self.baseURL = baseURL
    self.conf = conf
  }
}

// MARK: SearchService

extension FanboyService: SearchService {
  public func suggest (
    term: String
  , cb: (NSError?, [Suggestion]?) -> Void)
  -> NSURLSessionDataTask? {
    if let url =  queryURL(baseURL, "suggest", term) {
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
          // If we reach this, we can assume there are no suggestions.
          return cb(nil, nil)
        }
        if let buf = data {
          if acc == nil {
            acc = NSMutableData(capacity: buf.length)
          }
          acc?.appendData(buf)
        }
      }
      let task = session.dataTaskWithURL(url)
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

  public func search (term: String, cb: (NSError?, [SearchResult]?) -> Void)
  -> NSURLSessionDataTask? {
    assert(false, "not implemented yet")
    return nil
  }
}

// MARK: NSURLSessionTaskDelegate

extension FanboyService: NSURLSessionTaskDelegate {
  public func URLSession(
    session: NSURLSession
  , task: NSURLSessionTask
  , didCompleteWithError error: NSError?) {
    if let cb = handlers[task] {
      cb(error, nil, true)
    } else {
      assert(false, "missing handler")
    }
    handlers[task] = nil
  }
}

// MARK: NSURLSessionDataDelegate

extension FanboyService: NSURLSessionDataDelegate {
  public func URLSession(
    session: NSURLSession
  , dataTask: NSURLSessionDataTask
  , didReceiveData data: NSData) {
    if dataTask.state == .Running {
      if let cb = handlers[dataTask] {
        cb(nil, data, false)
      } else {
        assert(false, "missing handler")
      }
    }
  }

  public func URLSession(
    session: NSURLSession
  , didBecomeInvalidWithError error: NSError?) {
    _session = nil
  }
}
