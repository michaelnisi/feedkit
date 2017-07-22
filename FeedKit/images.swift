//
//  images.swift
//  Podest
//
//  Created by Michael on 3/19/17.
//  Copyright © 2017 Michael Nisi. All rights reserved.
//

import Foundation
import ImageIO
import Nuke
import UIKit
import os.log

// MARK: - Logging

@available(iOS 10.0, *)
fileprivate let log = OSLog(subsystem: "ink.codes.feedkit", category: "images")

// Typealiasing Nuke.Cache to prevent collision with FeedKit.Cache.
typealias ImageCache = Nuke.Cache

// MARK: - API

public protocol Images {
  func loadImage(for item: Imaginable, into imageView: UIImageView)
  func image(for item: Imaginable, in size: CGSize) -> UIImage?
  func preheatImage(for item: Imaginable, at size: CGSize)
}

// MARK: -

private struct Scale: Processing {
  let size: CGSize

  init(size: CGSize) {
    self.size = size
  }
  
  private func imageWithRoundedCorners(from image: UIImage) -> UIImage {
    UIGraphicsBeginImageContextWithOptions(size, false, 0)
    
    let cornerRadius: CGFloat = size.width <= 100 ? 3 : 6
    
    // TODO: Consider drawing a light border around images
    
    let rect = CGRect(x: 0, y: 0, width: size.width, height: size.height)
    UIBezierPath(roundedRect:rect, cornerRadius: cornerRadius).addClip()
    image.draw(in: rect)
    let rounded: UIImage = UIGraphicsGetImageFromCurrentImageContext()!
    
    UIGraphicsEndImageContext()
    
    return rounded
  }

  /// Returns scaled `image` with rounded corners.
  func process(_ image: UIImage) -> UIImage? {
    return imageWithRoundedCorners(from: image)
  }

  static func ==(lhs: Scale, rhs: Scale) -> Bool {
    return lhs.size == rhs.size
  }
}

/// Picks and returns the optimal image URL for `size`.
///
/// - Parameters:
///   - item: The image URL container.
///   - size: The size to choose an URL for.
///
/// - Returns: An image URL or `nil` if the item doesn’t contain one of the
/// expected URLs.
fileprivate func urlToLoad(from item: Imaginable, for size: CGSize) -> URL? {
  let wanted = size.width * UIScreen.main.scale
  
  var urlString: String?
  
  if wanted <= 30 {
    urlString = item.iTunes?.img30
  } else if wanted <= 60 {
    urlString = item.iTunes?.img60
  } else if wanted <= 100 {
    urlString = item.iTunes?.img100
  } else {
    urlString = item.iTunes?.img600
  }
  
  if urlString == nil {
    if let entry = item as? Entry {
      urlString = entry.feedImage
    }
    urlString = urlString ?? item.image
  }
  
  guard let string = urlString, let url = URL(string: string) else {
    return nil
  }
  
  return url
}

/// Picks a URL to load a smaller, a quarter of the actual target size, image, 
/// while the actual size is being loaded. If the requested size is too small 
/// for this to make sense or the item doesn’t contain suitable URLs, `nil` is 
/// returned.
/// 
/// - Parameters:
///   - item: The concerned item.
///   - size: The target size the loaded image will get scaled to.
///
/// - returns: The image URL or `nil`.
fileprivate func urlToPreload(from item: Imaginable, for size: CGSize) -> URL? {
  guard size.width > 60 else { return nil }
  
  let wanted = size.width * UIScreen.main.scale / 4
  return urlToLoad(from: item, for: CGSize(width: wanted, height: wanted))
}

public final class ImageRepository: Images {
  
  // TODO: Remove Singleton object
  
  public static var shared: Images = ImageRepository()
  
  public init() {}
  
  /// Synchronously loads an image for the specificied item and size.
  public func image(for item: Imaginable, in size: CGSize) -> UIImage? {
    guard let url = urlToLoad(from: item, for: size) else {
      return nil
    }
    
    // TODO: Don‘t round corners here
    
    let req = Request(url: url).processed(with: Scale(size: size))
    
    if let image = ImageCache.shared[req] {
      return image
    }
    
    guard let imageSource = CGImageSourceCreateWithURL(url as CFURL, nil) else {
      return nil
    }
    
    let options: [NSString: NSObject] = [
      kCGImageSourceThumbnailMaxPixelSize: max(size.width, size.height) as NSObject,
      kCGImageSourceCreateThumbnailFromImageAlways: true as NSObject
    ]
    
    let cgImage = CGImageSourceCreateThumbnailAtIndex(
      imageSource, 0, options as CFDictionary)
    let img = UIImage(cgImage: cgImage!)
    
    ImageCache.shared[req] = img
    
    return img
  }
  
  public func preheatImage(for item: Imaginable, at size: CGSize) {
    // TODO: Write
  }
  
  /// Loads an image to represent `item` into `imageView`, scaling the image
  /// to match the image view’s bounds.
  ///
  /// - Parameters:
  ///   - item: The item the loaded image should represent.
  ///   - imageView: The target view to display the image.
  public func loadImage(for item: Imaginable, into imageView: UIImageView) {
    let size = imageView.frame.size
    
    guard let url = urlToLoad(from: item, for: size) else {
      if #available(iOS 10.0, *) {
        os_log("no image: %{public}@", log: log,  type: .error,
               String(describing: item))
      }
      return
    }

    func load(url: URL, into view: UIImageView?, cb: @escaping Manager.Handler) {
      var urlReq = URLRequest(url: url)
      urlReq.cachePolicy = .returnCacheDataElseLoad
      
      let proc = Scale(size: size)
      let req = Request(urlRequest: urlReq).processed(with: proc)
      
      guard let v = view else { return }
      
      if #available(iOS 10.0, *) {
        os_log("loading image: %{public}@ %{public}@", log: log, type: .debug,
               url as CVarArg, size as CVarArg)
      }
      
      Nuke.loadImage(with: req, into: v, handler: cb)
    }
    
    if let smallURL = urlToPreload(from: item, for: size) {
      load(url: smallURL, into: imageView) { [weak imageView] res, _ in
        imageView?.image = res.value
        load(url: url, into: imageView) { [weak imageView] res, _ in
          imageView?.image = res.value
        }
      }
    } else {
      load(url: url, into: imageView) { [weak imageView] res, _ in
        imageView?.image = res.value
      }
    }
  }
}
