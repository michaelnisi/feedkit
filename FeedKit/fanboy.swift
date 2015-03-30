//
//  fanboy.swift
//  FeedKit
//
//  Created by Michael Nisi on 08.10.14.
//  Copyright (c) 2014 Michael Nisi. All rights reserved.
//

import Foundation
import Skull

func queryFromString (term: String) -> String? {
  let query = trimString(term, joinedByString: "+")
  return query.isEmpty ? nil : query
}

func queryURL (baseURL: NSURL, verb: String, term: String) -> NSURL? {
  if let query = queryFromString(term) {
    return NSURL(string: "\(verb)?q=\(query)", relativeToURL: baseURL)
  }
  return nil
}

func imagesFromDictionary (dict: Map) -> ITunesImages? {
  if let img100 = urlFromDictionary(dict, withKey: "img100") {
    if let img30 = urlFromDictionary(dict, withKey: "img30") {
      if let img600 = urlFromDictionary(dict, withKey: "img600") {
        if let img60 = urlFromDictionary(dict, withKey: "img60") {
          return ITunesImages(
            img100: img100
          , img30: img30
          , img600: img600
          , img60: img60)
        }
      }
    }
  }
  return nil
}

func searchResultFromDictionary (dict: Map) -> (NSError?, SearchResult?) {
  if let author = dict["author"] as? String {
    if let feed = urlFromDictionary(dict, withKey: "feed") {
      if let guid = dict["guid"] as? Int {
        if let images = imagesFromDictionary(dict) {
          if let title = dict["title"] as? String {
            return (nil, SearchResult(
              author: author
            , feed: feed
            , guid: guid
            , images: images
            , title: title
            , ts: nil
            ))
          }
        }
      }
    }
  }
  let info = ["message": "missing fields in \(dict)"]
  let er = NSError(domain: domain, code: 1, userInfo: info)
  return (er, nil)
}


func searchResultsFrom (dicts: [[String:AnyObject]]) -> (NSError?, [SearchResult]?) {
  if dicts.isEmpty { return (nil, nil) }
  var er: NSError?
  var results = [SearchResult]()
  var errors = [NSError]()
  for dict in dicts {
    let (er, result) = searchResultFromDictionary(dict)
    if er != nil { errors.append(er!) }
    if result != nil { results.append(result!) }
  }
  if errors.count > 0 {
    let info = ["message": messageFromErrors(errors)]
    er = NSError(domain: domain, code: 1, userInfo: info)
  }
  return (er, results)
}

func suggestionsFrom (terms: [String]) -> (NSError?, [Suggestion]?) {
  if terms.count < 1 {
    return (nil, nil)
  }
  let suggestions = terms.map { (term) -> Suggestion in
    return Suggestion(term: term, ts: nil)
  }
  return (nil, suggestions)
}

public class FanboyService: NSObject {
  public let baseURL: NSURL

  public var conf: NSURLSessionConfiguration {
    didSet {
      self._session = nil
    }
  }

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

  public init (
    baseURL: NSURL, conf: NSURLSessionConfiguration) {
    self.baseURL = baseURL
    self.conf = conf
  }

  var certs = [NSURL: SecCertificate]()
  public func removeCertificateAtURL (url: NSURL) {
    certs[url] = nil
  }
  public func addCertificateAtURL (url: NSURL) -> NSError? {
    var er: NSError?
    let bundle = NSBundle(forClass: self.dynamicType)
    let data = NSData(
      contentsOfURL: url, options: .DataReadingUncached, error: &er)
    let cfcert = SecCertificateCreateWithData(nil, data)
    let cert = cfcert.takeUnretainedValue()
    certs[url] = cert
    return er
  }
}

// MARK: SearchService

extension FanboyService: SearchService {
  public var allowsCellularAccess: Bool {
    get {
      return self.session.configuration.allowsCellularAccess
    }
  }

  func taskWithVerb (
    verb: String, forTerm term: String) -> NSURLSessionDataTask? {
    if let url = queryURL(baseURL, verb, term) {
      let req = NSMutableURLRequest(URL: url)
      return session.dataTaskWithRequest(req)
    }
    return nil
  }
  func searchTaskForTerm (term: String) -> NSURLSessionDataTask? {
    return taskWithVerb("search", forTerm: term)
  }
  func suggestTaskForTerm (term: String) -> NSURLSessionDataTask? {
    return taskWithVerb("suggest", forTerm: term)
  }

  public func suggest (
    term: String
  , cb: (NSError?, [Suggestion]?) -> Void) -> NSURLSessionDataTask? {
    if let task = suggestTaskForTerm(term) {
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
          return cb(nil, [])
        }
        if let buf = data {
          if acc == nil {
            acc = NSMutableData(capacity: buf.length)
          }
          acc?.appendData(buf)
        }
      }
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
    if let task = searchTaskForTerm(term) {
      var acc: NSMutableData?
      func handler (error: NSError?, data: NSData?, done: Bool) -> Void {
        if let er = error {
          return cb(er, nil)
        }
        if done {
          let (error, json: AnyObject?) = parseJSON(acc!)
          NSLog("Parsed JSON")
          if let er = error {
            return cb(er, nil)
          }
          if let items = json as? [[String:AnyObject]] {
            let (error, searchResults) = searchResultsFrom(items)
            NSLog("Created results")
            if let er = error {
              return cb(er, nil)
            }
            if let results = searchResults {
              return cb(nil, results)
            }
          }
          // If we reach this, we can assume there are no results.
          return cb(nil, [])
        }
        if let buf = data {
          if acc == nil {
            acc = NSMutableData(capacity: buf.length)
          }
          acc?.appendData(buf)
        }
      }
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

// MARK: NSURLSessionDelegate

extension FanboyService: NSURLSessionDelegate {
  public func URLSession(
    session: NSURLSession
    , didBecomeInvalidWithError error: NSError?) {
      _session = nil
  }

  public func URLSession(
    session: NSURLSession
  , didReceiveChallenge challenge: NSURLAuthenticationChallenge
  , completionHandler: (
      NSURLSessionAuthChallengeDisposition, NSURLCredential!) -> Void
  ) {
    let space = challenge.protectionSpace
    let theCerts = [SecCertificate](certs.values)
    let status = SecTrustSetAnchorCertificates(
      space.serverTrust, theCerts)
    completionHandler(.PerformDefaultHandling, nil)
  }
}

// MARK: NSURLSessionTaskDelegate

extension FanboyService: NSURLSessionTaskDelegate {
  public func URLSession(
    session: NSURLSession
  , task: NSURLSessionTask
  , didCompleteWithError error: NSError?) {
    if let cb = handlers[task] {
      handlers[task] = nil
      cb(error, nil, true)
    } else {
      assert(false, "missing handler")
    }
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
}
