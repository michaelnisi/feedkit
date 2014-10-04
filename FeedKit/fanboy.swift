//
//  fanboy.swift
//  FeedKit
//
//  Created by Michael Nisi on 27.09.14.
//  Copyright (c) 2014 Michael Nisi. All rights reserved.
//

import Foundation

public class Fanboy: Service, SearchService {
  public func search (query: String, cb: ((NSError?, ServiceResult?) -> Void)) {
  }
  
  public func suggest (term: String, cb: ((NSError?, ServiceResult?) -> Void)) {
  }
}

public class FanboyHTTP: Fanboy {
  override func makeBaseURL() -> NSURL? {
    return NSURL(string: "http://" + self.host + ":" + String(self.port))
  }
}
