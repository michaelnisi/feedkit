//
//  SuggestionsViewController.swift
//  crasher
//
//  Created by Michael Nisi on 04.11.14.
//  Copyright (c) 2014 Michael Nisi. All rights reserved.
//

import Foundation
import UIKit
import FeedKit

class SuggestionsViewController: UIViewController {
  var sugs: [Suggestion]?
  var repo: SearchRepository?
  
  override func viewDidAppear(animated: Bool) {
    super.viewDidAppear(animated)
    self.dismissViewControllerAnimated(false, completion: nil)
  }
  
  override func viewDidLoad() {
    super.viewDidLoad()
    // Do any additional setup after loading the view, typically from a nib.
    
    let svcQueue = NSOperationQueue()
    let svc = FanboyService(host: "localhost", port: 8383, queue: svcQueue)
    
    let repoQueue = NSOperationQueue()
    let cache = Cache() // TODO: Not sure if like this opaque initializer.
    repo = SearchRepository(queue: repoQueue, svc: svc, cache: cache)
    
    var sugs = self.sugs
    repo?.suggest("china", cb: { (error, suggestions) -> Void in
      if let er = error {
        println(er)
      }
      sugs = suggestions
      println("suggested: \(sugs)")
      }, end: { error -> Void in
        println("ok")
    })
  }
  
  override func didReceiveMemoryWarning() {
    super.didReceiveMemoryWarning()
    // Dispose of any resources that can be recreated.
  }
}
