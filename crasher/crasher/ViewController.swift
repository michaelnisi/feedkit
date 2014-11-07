//
//  ViewController.swift
//  crasher
//
//  Created by Michael Nisi on 04.11.14.
//  Copyright (c) 2014 Michael Nisi. All rights reserved.
//

import UIKit
import FeedKit

class ViewController: UIViewController {
  
  
  @IBAction func go(sender: AnyObject) {
    let vc = SuggestionsViewController()
    self.presentViewController(vc, animated: false, completion: nil)
  }
}

