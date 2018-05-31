//
//  images.swift - Load images
//  Podest
//
//  Created by Michael on 3/19/17.
//  Copyright © 2017 Michael Nisi. All rights reserved.
//

import Foundation
import Nuke
import UIKit
import os.log

fileprivate let log = OSLog(subsystem: "ink.codes.feedkit", category: "images")

// Hiding Nuke from participants.
public typealias ImageRequest = Nuke.ImageRequest

// MARK: - API

public enum ImageQuality: CGFloat {
  case high = 1
  case medium = 2
  case low = 4
}

public protocol Imaginable {
  var iTunes: ITunesItem? { get }
  var image: String? { get }
}

public protocol Images {

  func loadImage(for item: Imaginable, into imageView: UIImageView)

  /// Loads an image to represent `item` into `imageView`, scaling the image
  /// to match the image view’s bounds. For larger sizes a smaller image gets
  /// preloaded and displayed first, which gets replaced when the large image
  /// has been loaded, unless `imageView` is already occupied by an image, in
  /// that case, that previous image is used as placeholder, while loading.
  ///
  /// - Parameters:
  ///   - item: The item the loaded image should represent.
  ///   - imageView: The target view to display the image.
  ///   - quality: The expected image quality.
  func loadImage(for item: Imaginable,
                 into imageView: UIImageView,
                 quality: ImageQuality?)

  /// Prefetches images of `items`, preheating the image cache.
  ///
  /// - Returns: The resulting image requests, these can be used to cancel
  /// this prefetching batch.
  func prefetchImages(for items: [Imaginable],
                      at size: CGSize,
                      quality: ImageQuality
  ) -> [ImageRequest]

  /// Cancels prefetching `requests`.
  func cancel(prefetching requests: [ImageRequest])

  /// Synchronously loads an image for the specificied item and size.
  func image(for item: Imaginable, in size: CGSize) -> UIImage?

}

fileprivate func scale(_ size: CGSize, to quality: ImageQuality?) -> CGSize {
  let q = quality?.rawValue ?? ImageQuality.high.rawValue
  let w = size.width / q
  let h = size.height / q
  return CGSize(width: w, height: h)
}

// MARK: -

private struct ScaledWithRoundedCorners: ImageProcessing {

  let size: CGSize

  init(size: CGSize) {
    self.size = size
  }

  /// Returns scaled `image` with rounded corners.
  func process(image: Image, context: ImageProcessingContext) -> Image? {
    UIGraphicsBeginImageContextWithOptions(size, true, 0)

    let ctx = UIGraphicsGetCurrentContext()!

    UIColor.white.setFill()
    ctx.fill(CGRect(x: 0, y: 0, width: size.width, height: size.height))

    let cornerRadius: CGFloat = size.width <= 100 ? 3 : 6
    let rect = CGRect(x: 0, y: 0, width: size.width, height: size.height)
    UIBezierPath(roundedRect:rect, cornerRadius: cornerRadius).addClip()
    image.draw(in: rect)
    let rounded: UIImage = UIGraphicsGetImageFromCurrentImageContext()!

    UIGraphicsEndImageContext()

    return rounded
  }

  static func ==(lhs: ScaledWithRoundedCorners, rhs: ScaledWithRoundedCorners) -> Bool {
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
    os_log("falling back on LARGE image", log: log)
    if let entry = item as? Entry {
      urlString = entry.feedImage
    }
    urlString = urlString ?? item.image
  }

  guard let string = urlString, let url = URL(string: string) else {
    os_log("no image URL", log: log, type: .error)
    return nil
  }

  return url
}

/// Picks a URL to load a smaller image to preload and show while the actual
/// size is being loaded. If the requested size is too small for this to
/// make sense or the item doesn’t contain suitable URLs, `nil` is returned.
///
/// - Parameters:
///   - item: The concerned item.
///   - size: The target size the loaded image will get scaled to.
///
/// - Returns: The image URL or `nil`.
private func urlToPreload(from item: Imaginable, for size: CGSize) -> URL? {
  guard size.width > 60 else {
    return nil
  }

  let s = min(size.width / 4, 100)
  return urlToLoad(from: item, for: CGSize(width: s, height: s))
}

/// Provides images. Images are cached, including their rounded corners, making
/// it impossible to get an image without rounded corners, at the moment.
public final class ImageRepository: Images {

  public static var shared: Images = ImageRepository()

  fileprivate let preheater = Nuke.ImagePreheater()

  public func image(for item: Imaginable, in size: CGSize) -> UIImage? {
    os_log("image for: %{public}@, %{public}@", log: log,  type: .debug,
           String(describing: item), String(describing: item.iTunes))

    guard let url = urlToLoad(from: item, for: size) else {
      return nil
    }

    var image: UIImage?
    let req = ImageRequest(url: url, targetSize: size, contentMode: .aspectFill)
    let blocker = DispatchSemaphore(value: 0)

    Nuke.ImagePipeline.shared.loadImage(with: req) { res, error in
      if let er = error {
        os_log("image loading error: %{public}@", log: log, er as CVarArg)
      }
      image = res?.image
      blocker.signal()
    }

    blocker.wait()

    return image
  }

  private static func load(
    url: URL,
    into view: UIImageView?,
    cb: @escaping ImageTask.Completion
  ) {
    var urlReq = URLRequest(url: url)
    urlReq.cachePolicy = .returnCacheDataElseLoad

    let proc = ScaledWithRoundedCorners(size: size)
    let req = ImageRequest(urlRequest: urlReq).processed(with: proc)

    guard let v = view else { return }

    os_log("loading image: %{public}@ %{public}@", log: log, type: .debug,
           url as CVarArg, size as CVarArg)

    guard let currentImage = v.image else {
      Nuke.loadImage(with: req, into: v, completion: cb)
      return
    }

    os_log("placeholding with current image", log: log, type: .debug)

    let opts = ImageLoadingOptions(
      placeholder: currentImage,
      transition: nil,
      failureImage: currentImage,
      failureImageTransition: nil,
      contentModes: nil
    )

    Nuke.loadImage(with: req, options: opts, into: v, completion: cb)
  }

  public func loadImage(
    for item: Imaginable,
    into imageView: UIImageView,
    quality: ImageQuality? = nil
  ) {
    let size = imageView.frame.size

    os_log("handling image request for: %@, with: %@, at: %@",
           log: log, type: .debug,
           String(describing: item),
           String(describing: item.iTunes),
           size as CVarArg)

    guard let url = urlToLoad(from: item, for: scale(size, to: quality)) else {
      os_log("no image: %{public}@", log: log,  type: .error,
             String(describing: item))
      return
    }

    if let smallURL = urlToPreload(from: item, for: size) {
      ImageRepository.load(url: smallURL, into: imageView) {
        [weak imageView] res, _ in
        DispatchQueue.main.async {
          imageView?.image = res?.image
        }
        DispatchQueue.main.async {
          ImageRepository.load(url: url, into: imageView) {
            [weak imageView] res, _ in
            DispatchQueue.main.async {
              imageView?.image = res?.image
            }
          }
        }
      }
    } else {
      ImageRepository.load(url: url, into: imageView) {
        [weak imageView] res, _ in
        DispatchQueue.main.async {
          imageView?.image = res?.image
        }
      }
    }
  }

  public func loadImage(for item: Imaginable, into imageView: UIImageView) {
    loadImage(for: item, into: imageView, quality: .high)
  }
}

// MARK: - Prefetching

extension ImageRepository {

  fileprivate func requests(
    with items: [Imaginable], at size: CGSize, quality: ImageQuality
  ) -> [ImageRequest] {
    return items.compactMap {
      guard let url = urlToLoad(from: $0, for: scale(size, to: quality)) else {
        return nil
      }
      return ImageRequest(url: url)
    }
  }

  public func prefetchImages(
    for items: [Imaginable], at size: CGSize, quality: ImageQuality
  ) -> [ImageRequest] {
    let reqs = requests(with: items, at: size, quality: quality)
    os_log("starting preheating: %{public}@", log: log, type: .debug, items)
    preheater.startPreheating(with: reqs)
    return reqs
  }

  public func cancel(prefetching requests: [ImageRequest]) {
    os_log("stopping preheating: %{public}@", log: log, type: .debug, requests)
    preheater.stopPreheating(with: requests)
  }

}
