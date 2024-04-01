//
//  VideoGeometry.swift
//  iina
//
//  Created by Matt Svoboda on 11/14/23.
//  Copyright © 2023 lhc. All rights reserved.
//

import Foundation

/// `VideoGeometry`: collection of metadata for the current video.Fetched from mpv.
///
/// Processing pipeline:
/// `videoSizeRaw` (`rawWidth`, `rawHeight`)
///   ➤ apply `aspectRatioOverride`
///     ➤ `videoSizeA`
///       ➤ apply `cropBox`
///         ➤ `videoSizeAC` (`videoWidthAC`, `videoHeightAC`). AKA "dsize", per mpv usage
///           ➤ apply `totalRotation`
///             ➤ `videoSizeACR` (`videoWidthACR`, `videoHeightACR`)
///               ➤ apply `scale`
///                 ➤ `videoSize` (`PWGeometry`)
struct VideoGeometry: CustomStringConvertible {
  static let nullSet = VideoGeometry(rawWidth: 0, rawHeight: 0,
                                     selectedAspectLabel: "",
                                     totalRotation: 0, userRotation: 0,
                                     selectedCropLabel: AppData.noneCropIdentifier,
                                     scale: 0)

  init(rawWidth: Int, rawHeight: Int,
       selectedAspectLabel: String,
       totalRotation: Int, userRotation: Int,
       selectedCropLabel: String,
       scale: CGFloat) {
    self.rawWidth = rawWidth
    self.rawHeight = rawHeight
    if let aspectRatioOverride = Aspect(string: selectedAspectLabel) {
      self.selectedAspectLabel = selectedAspectLabel
      self.aspectRatioOverride = Aspect.mpvPrecision(of: aspectRatioOverride.value)
    } else {
      self.selectedAspectLabel = AppData.defaultAspectIdentifier
      self.aspectRatioOverride = nil
    }
    self.totalRotation = totalRotation
    self.userRotation = userRotation
    self.selectedCropLabel = selectedCropLabel
    self.cropBox = VideoGeometry.makeCropBox(fromCropLabel: selectedCropLabel, rawWidth: rawWidth, rawHeight: rawHeight)
    self.scale = scale
  }

  // FIXME: make this the SST for scale, instead of calculating it afterwards
  func clone(rawWidth: Int? = nil, rawHeight: Int? = nil,
             selectedAspectLabel: String? = nil,
             totalRotation: Int? = nil, userRotation: Int? = nil,
             selectedCropLabel: String? = nil,
             scale: CGFloat? = nil) -> VideoGeometry {
    return VideoGeometry(rawWidth: rawWidth ?? self.rawWidth, rawHeight: rawHeight ?? self.rawHeight,
                         selectedAspectLabel: selectedAspectLabel ?? self.selectedAspectLabel,
                         totalRotation: totalRotation ?? self.totalRotation, userRotation: userRotation ?? self.userRotation,
                         selectedCropLabel: selectedCropLabel ?? self.selectedCropLabel,
                         scale: scale ?? self.scale)

  }

  /// Current video's native stored dimensions, before aspect correction applied.
  /// From the mpv manual:
  /// ```
  /// width, height
  ///   Video size. This uses the size of the video as decoded, or if no video frame has been decoded yet,
  ///   the (possibly incorrect) container indicated size.
  /// ```
  let rawWidth: Int
  let rawHeight: Int

  /// The native size of the current video, before any filters, rotations, or other transformations applied.
  /// Returns `nil` if its width or height is considered missing or invalid (i.e., not positive)
  var videoSizeRaw: CGSize? {
    guard rawWidth > 0, rawHeight > 0 else { return nil}
    return CGSize(width: rawWidth, height: rawHeight)
  }

  // SECTION: Aspect

  /// The currently applied aspect, used for finding current aspect in menu & sidebar segmented control. Does not include rotation(s)
  let selectedAspectLabel: String

  /// Truncates aspect to the first 2 digits after decimal.
  let aspectRatioOverride: CGFloat?

  /// Same as `videoSizeRaw` but with aspect ratio override applied. If no aspect ratio override, then identical to `videoSizeRaw`.
  var videoSizeA: CGSize? {
    guard let videoSizeRaw else { return nil }

    return VideoGeometry.applyAspectOverride(aspectRatioOverride, to: videoSizeRaw)
  }

  // SECTION: Aspect + Crop

  let selectedCropLabel: String

  /// This is derived from `selectedCropLabel`, but has its Y value flipped so that it works with Cocoa views.
  let cropBox: CGRect?

  /// The video size, after aspect override and crop filter applied, but before rotation or final scaling.
  ///
  /// From the mpv manual:
  /// ```
  /// dwidth, dheight
  /// Video display size. This is the video size after filters and aspect scaling have been applied. The actual
  /// video window size can still be different from this, e.g. if the user resized the video window manually.
  /// These have the same values as video-out-params/dw and video-out-params/dh.
  /// ```
  var videoSizeAC: CGSize? {
    guard let videoSizeRaw, let videoSizeA else {
      return nil
    }
    let widthMultiplier = videoSizeA.width / videoSizeRaw.width
    let heightMultiplier = videoSizeA.height / videoSizeRaw.height

    if let cropBox {
      return CGSize(width: cropBox.width * widthMultiplier, height: cropBox.height * heightMultiplier)
    }
    return videoSizeA
  }

  /// Same as mpv `dwidth`. See docs for `videoSizeAC`.
  var videoWidthAC: Int? {
    guard let videoSizeAC else { return nil }
    return Int(videoSizeAC.width)
  }
  /// Same as mpv `dheight`. See docs for `videoSizeAC`.
  var videoHeightAC: Int? {
    guard let videoSizeAC else { return nil }
    return Int(videoSizeAC.height)
  }

  /// `MPVProperty.videoGeoRotate`.
  ///
  /// Is refreshed as property change events arrive for `MPVProperty.videoGeoRotate` ("video-params/rotate")
  /// IINA only supports one of [0, 90, 180, 270]
  let totalRotation: Int

  /// `MPVProperty.videoRotate`.
  ///
  /// Is refreshed as property change events arrive for `MPVOption.Video.videoRotate` ("video-rotate").
  /// Not to be confused with the `MPVProperty.videoGeoRotate` ("video-params/rotate")
  let userRotation: Int

  var isWidthSwappedWithHeightByRotation: Bool {
    // 90, 270, etc...
    (totalRotation %% 180) != 0
  }

  // SECTION: Aspect + Crop + Rotation

  /// Like `dwidth`, but after applying `totalRotation`.
  var videoWidthACR: Int? {
    if isWidthSwappedWithHeightByRotation {
      return videoHeightAC
    } else {
      return videoWidthAC
    }
  }

  /// Like `dheight`, but after applying `totalRotation`.
  var videoHeightACR: Int? {
    if isWidthSwappedWithHeightByRotation {
      return videoWidthAC
    } else {
      return videoHeightAC
    }
  }

  /// Like `videoSizeAC`, but after applying `totalRotation`.
  var videoSizeACR: CGSize? {
    guard let videoWidthACR, let videoHeightACR else { return nil }
    return CGSize(width: videoWidthACR, height: videoHeightACR)
  }

  var hasValidSize: Bool {
    return videoWidthACR != nil && videoHeightACR != nil
  }

  var videoAspectACR: CGFloat? {
    guard let videoSizeACR else { return nil }
    return videoSizeACR.mpvAspect
  }

  /// `MPVProperty.windowScale`:
  var scale: CGFloat

  /// Like `videoSizeACR`, but after applying `scale`.
  var videoSizeACRS: CGSize? {
    guard let videoSizeACR else { return nil }
    return CGSize(width: round(videoSizeACR.width * scale),
                  height: round(videoSizeACR.height * scale))
  }

  /// Final aspect ratio of `videoView` (scale-invariant)
  var videoViewAspect: CGFloat? {
    return videoAspectACR
  }

  // Etc

  var description: String {
    return "VideoGeometry:{vidSizeRaw=\(rawWidth)x\(rawHeight), vidSizeAC=\(videoWidthAC?.description ?? "nil")x\(videoHeightAC?.description ?? "nil") selectedAspectLabel=\(selectedAspectLabel.quoted) aspectOverride=\(aspectRatioOverride?.description.quoted ?? "nil") rotTotal=\(totalRotation) rotUser=\(userRotation) cropLabel=\(selectedCropLabel) cropBox=\(cropBox?.debugDescription ?? "nil") scale=\(scale), aspectACR=\(videoAspectACR?.description ?? "nil") vidSizeACR=\(videoSizeACR?.debugDescription ?? "nil")}"
  }

  // Static utils

  /// Adjusts the dimensions of the given `CGSize` as needed to match the given aspect
  static func applyAspectOverride(_ newAspect: CGFloat?, to origSize: CGSize) -> CGSize {
    guard let newAspect else {
      // No aspect override
      return origSize
    }
    let origAspect = origSize.mpvAspect
    if origAspect > newAspect {
      return CGSize(width: origSize.width, height: round(origSize.height * origAspect / newAspect))
    }
    return CGSize(width: round(origSize.width / origAspect * newAspect), height: origSize.height)
  }

  private static func makeCropBox(fromCropLabel cropLabel: String, rawWidth: Int, rawHeight: Int) -> CGRect? {
    if cropLabel == AppData.noneCropIdentifier {
      return nil
    }

    let videoRawSize = CGSize(width: rawWidth, height: rawHeight)

    if let aspect = Aspect(string: cropLabel) {
      return videoRawSize.getCropRect(withAspect: aspect)
    } else {
      let split1 = cropLabel.split(separator: "x")
      if split1.count == 2 {
        if split1[1].firstIndex(of: "+") == nil {
          let params: [String: String] = [
            "w": String(split1[0]),
            "h": String(split1[1])
          ]
          return MPVFilter.cropRect(fromParams: params, origVideoSize: videoRawSize, flipY: true)
        }

        let split2 = split1[1].split(separator: "+")
        if split2.count == 3 {
          let params: [String: String] = [
            "w": String(split1[0]),
            "h": String(split2[0]),
            "x": String(split2[1]),
            "y": String(split2[2])
          ]
          return MPVFilter.cropRect(fromParams: params, origVideoSize: videoRawSize, flipY: true)
        }
      }
      Logger.log("Could not parse crop from label: \(cropLabel.quoted)", level: .error)
      return nil
    }
  }

}
