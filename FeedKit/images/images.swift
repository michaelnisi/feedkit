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
  var title: String { get }
}

/// Configures image loading.
public struct FKImageLoadingOptions {

  let fallbackImage: UIImage?
  let quality: ImageQuality
  let isDirect: Bool

  /// Creates new options for image loading.
  ///
  /// For larger sizes a smaller image gets preloaded and displayed first,
  /// which gets replaced when the large image has been loaded. Use `isDirect`
  /// to skip this preloading step.
  ///
  /// - Parameters:
  ///   - fallbackImage: A failure image for using as fallback.
  ///   - quality: The image quality defaults to medium.
  ///   - isDirect: Skip preloading smaller images, which is the default.
  public init(
    fallbackImage: UIImage? = nil,
    quality: ImageQuality = .medium,
    isDirect: Bool = false
  ) {
    self.fallbackImage = fallbackImage
    self.quality = quality
    self.isDirect = isDirect
  }

}

public protocol Images {

  /// Loads an image to represent `item` into `imageView`, scaling the image
  /// to match the image view’s bounds.
  ///
  /// Passing no result to the completion block of this high level image loader.
  ///
  /// - Parameters:
  ///   - item: The item the loaded image should represent.
  ///   - imageView: The target view to display the image.
  ///   - options: Some options for image loading.
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

  /// Loads an image using default options: falling back on existing image,
  /// medium quality, and preloading smaller images for large sizes.
  func loadImage(representing item: Imaginable, into imageView: UIImageView)

  /// Prefetches images of `items`, preheating the image cache.
  ///
  /// - Returns: The resulting image requests, these can be used to cancel
  /// this prefetching batch.
  func prefetchImages(
    for items: [Imaginable],
    at size: CGSize,
    quality: ImageQuality
  ) -> [ImageRequest]

  /// Cancels prefetching `requests`.
  func cancel(prefetching requests: [ImageRequest])

  /// Cancels request associated with `view`.
  func cancel(displaying view: UIImageView)

  /// Synchronously loads an image for the specificied item and size.
  func image(for item: Imaginable, in size: CGSize) -> UIImage?

  /// Flushes memory cache.
  func flush()

}
