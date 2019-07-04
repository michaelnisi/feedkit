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

/// Represents an image request.
public typealias ImageRequest = Nuke.ImageRequest

/// Enumerates possible image qualities (100%, 50%, 25%).
public enum ImageQuality: CGFloat {
  case high = 1
  case medium = 2
  case low = 4
}

/// An item for which an image can be loaded.
public protocol Imaginable {
  var iTunes: ITunesItem? { get }
  var image: String? { get }
  var title: String { get }
}

/// Configures image loading.
public struct FKImageLoadingOptions {

  /// A failure image for using as a fallback.
  let fallbackImage: UIImage?

  /// The image quality defaults to medium.
  let quality: ImageQuality

  /// Skip preloading smaller images, which is the default.
  let isDirect: Bool

  /// Skip processing, just load.
  let isClean: Bool

  /// Creates new options for image loading.
  ///
  /// For larger sizes a smaller image gets preloaded and displayed first,
  /// getting replaced when the large image has been loaded. Use `isDirect`
  /// to skip this preloading step.
  public init(
    fallbackImage: UIImage? = nil,
    quality: ImageQuality = .medium,
    isDirect: Bool = false,
    isClean: Bool = false
  ) {
    self.fallbackImage = fallbackImage
    self.quality = quality
    self.isDirect = isDirect
    self.isClean = isClean
  }
}

/// An image loading API.
public protocol Images {

  /// Loads an image representing`item` into `imageView`, scaling the image
  /// to match the image view’s bounds size.
  ///
  /// Smallest possible latency is critical here.
  ///
  /// - Parameters:
  ///   - item: The item the loaded image should represent.
  ///   - imageView: The target view to display the image.
  ///   - options: Some options specify details about how to load this image.
  ///   - completionBlock: A block to execute when the image has been loaded.
  func loadImage(
    representing item: Imaginable,
    into imageView: UIImageView,
    options: FKImageLoadingOptions,
    completionBlock: (() -> Void)?
  )

  func loadImage(
    representing item: Imaginable,
    into imageView: UIImageView,
    options: FKImageLoadingOptions
  )

  /// Loads an image using default options, falling back on existing image,
  /// medium quality, and preloading smaller images for large sizes.
  func loadImage(representing item: Imaginable, into imageView: UIImageView)

  /// Prefetches images of `items`, preheating the image cache.
  ///
  /// - Returns: The resulting image requests, these can be used to cancel
  /// this prefetching batch.
  @discardableResult
  func prefetchImages(
    for items: [Imaginable], at size: CGSize, quality: ImageQuality
  ) -> [ImageRequest]

  /// Cancels prefetching images for `items` at `size` of `quality`.
  func cancelPrefetching(
     _ items: [Imaginable], at size: CGSize, quality: ImageQuality)

  /// Cancels prefetching `requests`.
  func cancel(prefetching requests: [ImageRequest])

  /// Cancels request associated with `view`.
  func cancel(displaying view: UIImageView)

  /// Synchronously loads image for specificied `item` at `size`.
  func loadImage(item: Imaginable, size: CGSize) -> UIImage?

  /// Flushes in-memory caches.
  func flush()
}
