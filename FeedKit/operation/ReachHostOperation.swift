//
//  ReachHostOperation.swift
//  FeedKit
//
//  Created by Michael Nisi on 16.02.18.
//  Copyright © 2018 Michael Nisi. All rights reserved.
//

import Foundation
import os.log
import Ola

private let log = OSLog.disabled

class ReachHostOperation: Operation, ProvidingReachability {
  var status = OlaStatus.unknown
  var error: Error?
  
  let host: String
  
  init(host: String) {
    self.host = host
  }
  
  override func main() {
    os_log("starting ReachHostOperation: %@", log: log, type: .debug, host)
    guard let probe = Ola(host: host) else {
      return
    }
    self.status = probe.reach()
  }
}
