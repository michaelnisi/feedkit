//===----------------------------------------------------------------------===//
//
// This source file is part of the FeedKit open source project
//
// Copyright (c) 2017 Michael Nisi and collaborators
// Licensed under MIT License
//
// See https://github.com/michaelnisi/feedkit/blob/main/LICENSE for license information
//
//===----------------------------------------------------------------------===//

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
    os_log("starting ReachHostOperation: %@", log: log, type: .info, host)
    guard let probe = Ola(host: host) else {
      return
    }
    self.status = probe.reach()
  }
}
