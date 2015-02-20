//
//  serialize.swift - some common serialization functions
//  FeedKit
//
//  Created by Michael Nisi on 10.02.15.
//  Copyright (c) 2015 Michael Nisi. All rights reserved.
//

import Foundation
import Skull

typealias Map = [String:AnyObject]

func trimString (s: String, joinedByString j:String = "") -> String {
  let ws = NSCharacterSet.whitespaceCharacterSet()
  let ts = s.stringByTrimmingCharactersInSet(ws)
  let cmps = ts.componentsSeparatedByString(" ") as [String]
  return cmps.reduce("") { a, b in
    if a.isEmpty { return b }
    let tb = b.stringByTrimmingCharactersInSet(ws)
    if tb.isEmpty { return a }
    return "\(a)\(j)\(tb)"
  }
}

func urlFromDictionary (dict: Map, withKey key: String) -> NSURL? {
  if let str = dict[key] as? String {
    return NSURL(string: str)
  }
  return nil
}

func dateFromDictionary (dict: Map, withKey key: String) -> NSDate? {
  if let value = dict[key] as? NSTimeInterval {
    return NSDate(timeIntervalSince1970: value / 1000)
  }
  return nil
}

func messageFromErrors (errors: [NSError]) -> String {
  var str: String = errors.count > 0 ? "" : "no errors"
  for error in errors {
    str += "\(error.description)\n"
  }
  return str
}

func parseJSON (data: NSData) -> (NSError?, AnyObject?) {
  var er: NSError?
  if let json: AnyObject = NSJSONSerialization.JSONObjectWithData(
    data
  , options: NSJSONReadingOptions.AllowFragments
  , error: &er) {
    return (er, json)
  }
  er = NSError(
    domain: domain
  , code: 1
  , userInfo: ["message": "couldn't create JSON object"]
  )
  return (er, nil)
}
