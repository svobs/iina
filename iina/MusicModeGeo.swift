//
//  MusicModeGeometry.swift
//  iina
//
//  Created by Matt Svoboda on 9/18/23.
//  Copyright © 2023 lhc. All rights reserved.
//

import Foundation

/**
 `MusicModeGeometry`: like `PWinGeometry`, but for music mode.

 Because the music mode window reuses the existing player window, it:
 * Uses the viewport to display video or album art, but can be turned off, in which case it is given a height of zero. The viewport has 0 margins on all sides when in music mode.
 * Uses the outside bottom bar for:
 * 1. Either current media info, or OSC on hover. This is always displayed in music mode and has constant height.
 * 2. Playlist if shown. Playlist has 0 height if hidden, otherwise is bounded by `minPlaylistHeight` and remaining height on screen.
 *  Never has any inside bars, outside sidebars or top bar (the views exist but are reduced to zero area).

 A `MusicModeGeometry` object can be converted to a `PWinGeometry` via its `toPWinGeometry()` function.
 */
struct MusicModeGeometry: Equatable, CustomStringConvertible {
  let windowFrame: NSRect
  let screenID: String
  let isVideoVisible: Bool
  let video: VideoGeometry

  /// indicates if playlist is currently visible
  var isPlaylistVisible: Bool {
    return playlistHeight > 0
  }

  /// If playlist if visible, indicates playlist height.
  /// Will be 0 if playlist is not visible.
  /// Derived from other properties.
  var playlistHeight: CGFloat {
    return round(windowFrame.height - videoHeight - Constants.Distance.MusicMode.oscHeight)
  }

  /// Indicates height of video / album art when it is visible, or what the height should be even if
  /// it is not visible.
  /// Derived from other properties.
  var videoHeightWhenVisible: CGFloat {
    return MusicModeGeometry.videoHeightWhenVisible(windowFrame: windowFrame, video: video)
  }

  /// Derived from other properties.
  var videoHeight: CGFloat {
    return isVideoVisible ? videoHeightWhenVisible : 0
  }

  var videoSize: NSSize? {
    guard isVideoVisible else { return nil }
    return NSSize(width: windowFrame.width, height: videoHeightWhenVisible)
  }

  var videoAspect: CGFloat {
    return video.videoViewAspect
  }

  var videoScale: Double {
    return windowFrame.width / video.videoSizeCAR.width
  }

  var viewportSize: NSSize? {
    return videoSize
  }

  var bottomBarHeight: CGFloat {
    return windowFrame.height - videoHeight
  }

  var log: Logger.Subsystem {
    return video.log
  }

  init(windowFrame: NSRect, screenID: String, video: VideoGeometry, isVideoVisible: Bool, isPlaylistVisible: Bool) {
    var windowFrame = NSRect(origin: windowFrame.origin, size:
                              CGSize(width: windowFrame.width.rounded(), height: windowFrame.height.rounded()))
    let videoHeight = MusicModeGeometry.videoHeight(windowFrame: windowFrame, video: video, isVideoVisible: isVideoVisible)
    let playlistHeight = windowFrame.height - videoHeight - Constants.Distance.MusicMode.oscHeight
    let log = video.log

    let extraWidthNeeded = Constants.Distance.MusicMode.minWindowWidth - windowFrame.width
    if extraWidthNeeded > 0 {
      if log.isTraceEnabled {
        log.trace{"MusicModeGeoInit: width too small; adding: \(extraWidthNeeded)"}
      }
      windowFrame = NSRect(origin: windowFrame.origin, size: CGSize(width: windowFrame.width + extraWidthNeeded, height: windowFrame.height))
    }

    if isPlaylistVisible {
      let extraHeightNeeded = Constants.Distance.MusicMode.minPlaylistHeight - playlistHeight
      if extraHeightNeeded > 0 {
        log.trace{"MusicModeGeoInit: height too small for playlist; adding: \(extraHeightNeeded)"}
        windowFrame = NSRect(x: windowFrame.origin.x, y: windowFrame.origin.y - extraHeightNeeded,
                             width: windowFrame.width, height: windowFrame.height + extraHeightNeeded)
      }
    } else {
      let extraHeightNeeded = -playlistHeight
      if extraHeightNeeded != 0 {
        log.trace{"MusicModeGeoInit: height is invalid; adding: \(extraHeightNeeded)"}
        windowFrame = NSRect(x: windowFrame.origin.x, y: windowFrame.origin.y - extraHeightNeeded,
                             width: windowFrame.width, height: windowFrame.height + extraHeightNeeded)
      }
    }
    assert(windowFrame.origin.x.isInteger && windowFrame.origin.y.isInteger && windowFrame.width.isInteger && windowFrame.height.isInteger,
          "All windowFrame dimensions must be integers: \(windowFrame)")
    self.windowFrame = windowFrame
    self.screenID = screenID
    self.isVideoVisible = isVideoVisible
    self.video = video
    assert(isPlaylistVisible ? (self.playlistHeight >= Constants.Distance.MusicMode.minPlaylistHeight) : (self.playlistHeight == 0),
           "Playlist height invalid: isPlaylistVisible==\(isPlaylistVisible.yn) but playlistHeight==\(self.playlistHeight) < min (\(Constants.Distance.MusicMode.minPlaylistHeight))")
  }

  func clone(windowFrame: NSRect? = nil, screenID: String? = nil, video: VideoGeometry? = nil,
             isVideoVisible: Bool? = nil, isPlaylistVisible: Bool? = nil) -> MusicModeGeometry {
    return MusicModeGeometry(windowFrame: windowFrame ?? self.windowFrame,
                             screenID: screenID ?? self.screenID,
                             video: video ?? self.video,
                             isVideoVisible: isVideoVisible ?? self.isVideoVisible,
                             isPlaylistVisible: isPlaylistVisible ?? self.isPlaylistVisible)
  }

  /// Converts this `MusicModeGeometry` to an equivalent `PWinGeometry` object.
  func toPWinGeometry() -> PWinGeometry {
    let winGeo = PWinGeometry(windowFrame: windowFrame,
                              screenID: screenID,
                              fitOption: .stayInside,
                              mode: .musicMode,
                              topMarginHeight: 0,
                              outsideBars: MarginQuad(bottom: Constants.Distance.MusicMode.oscHeight + playlistHeight),
                              insideBars: MarginQuad.zero,
                              video: video)

    assert(winGeo.isVideoVisible == self.isVideoVisible)
    return winGeo
  }

  func hasEqual(windowFrame windowFrame2: NSRect? = nil, videoSize videoSize2: NSSize? = nil) -> Bool {
    return PWinGeometry.areEqual(windowFrame1: windowFrame, windowFrame2: windowFrame2, videoSize1: videoSize, videoSize2: videoSize2)
  }

  func withVideoViewVisible(_ visible: Bool) -> MusicModeGeometry {
    guard self.isVideoVisible != visible else { return self }

    var newWindowFrame = windowFrame
    if visible {
      newWindowFrame.size.height += videoHeightWhenVisible
    } else {
      // If playlist is also hidden, do not try to shrink smaller than the control view, which would cause
      // a constraint violation. This is possible due to small imprecisions in various layout calculations.
      newWindowFrame.size.height = max(Constants.Distance.MusicMode.oscHeight, newWindowFrame.size.height - videoHeightWhenVisible)
    }
    return clone(windowFrame: newWindowFrame, isVideoVisible: visible)
  }

  /// The MiniPlayerWindow's width must be between `MiniPlayerMinWidth` and `Preference.musicModeMaxWidth`.
  /// It is composed of up to 3 vertical sections:
  /// 1. `videoWrapperView`: Visible if `isVideoVisible` is true). Scales with the aspect ratio of its video
  /// 2. `musicModeControlBarView`: Visible always. Fixed height
  /// 3. `playlistWrapperView`: Visible if `isPlaylistVisible` is true. Height is user resizable, and must be >= `PlaylistMinHeight`
  /// Must also ensure that window stays within the bounds of the screen it is in. Almost all of the time the window  will be
  /// height-bounded instead of width-bounded.
  func refit() -> MusicModeGeometry {
    let containerFrame = PWinGeometry.getContainerFrame(forScreenID: screenID, fitOption: .stayInside)!

    /// When the window's width changes, the video scales to match while keeping its aspect ratio,
    /// and the control bar (`musicModeControlBarView`) and playlist are pushed down.
    /// Calculate the maximum width/height the art can grow to so that `musicModeControlBarView` is not pushed off the screen.
    let minPlaylistHeight = isPlaylistVisible ? Constants.Distance.MusicMode.minPlaylistHeight : 0
    let videoAspect = video.videoViewAspect

    var maxWidth: CGFloat
    if isVideoVisible {
      var maxVideoHeight = containerFrame.height - Constants.Distance.MusicMode.oscHeight - minPlaylistHeight
      /// `maxVideoHeight` can be negative if very short screen! Fall back to height based on `MiniPlayerMinWidth` if needed
      maxVideoHeight = max(maxVideoHeight, round(Constants.Distance.MusicMode.minWindowWidth / videoAspect))
      maxWidth = round(maxVideoHeight * videoAspect)
    } else {
      maxWidth = MiniPlayerViewController.maxWindowWidth
    }
    maxWidth = min(maxWidth, containerFrame.width)

    // Determine width first
    let newWidth: CGFloat
    let requestedSize = windowFrame.size
    if requestedSize.width < Constants.Distance.MusicMode.minWindowWidth {
      // Clamp to min width
      newWidth = Constants.Distance.MusicMode.minWindowWidth
    } else if requestedSize.width > maxWidth {
      // Clamp to max width
      newWidth = maxWidth
    } else {
      // Requested size is valid
      newWidth = requestedSize.width
    }

    // Now determine height
    let videoHeight = isVideoVisible ? round(newWidth / videoAspect) : 0
    let minWindowHeight = videoHeight + Constants.Distance.MusicMode.oscHeight + minPlaylistHeight
    // Make sure height is within acceptable values
    var newHeight = max(requestedSize.height, minWindowHeight)
    let maxHeight = isPlaylistVisible ? containerFrame.height : minWindowHeight
    newHeight = min(round(newHeight), maxHeight)
    let newWindowSize = NSSize(width: newWidth, height: newHeight)

    var newWindowFrame = NSRect(origin: windowFrame.origin, size: newWindowSize)
    if ScreenFitOption.stayInside.shouldMoveWindowToKeepInContainer {
      newWindowFrame = newWindowFrame.constrain(in: containerFrame)
    }
    let fittedGeo = self.clone(windowFrame: newWindowFrame)
    log.verbose("Refitted \(fittedGeo), from requestedSize: \(requestedSize)")
    return fittedGeo
  }

  func scaleViewport(to desiredSize: NSSize? = nil,
                     screenID: String? = nil) -> MusicModeGeometry? {
    return scaleVideo(to: desiredSize?.width, screenID: screenID)
  }

  func scaleVideo(to desiredWidth: CGFloat? = nil,
                  screenID: String? = nil) -> MusicModeGeometry? {

    var newVideoWidth = desiredWidth ?? windowFrame.width
    log.verbose("Scaling MusicMode video to desiredWidth: \(newVideoWidth)")

    let newScreenID = screenID ?? self.screenID
    let containerFrame: NSRect = PWinGeometry.getContainerFrame(forScreenID: newScreenID, fitOption: .stayInside)!

    // Window height should not change. Only video size should be scaled
    let windowHeight = min(containerFrame.height, windowFrame.height)

    // Constrain desired width within min and max allowed, then recalculate height from new value
    newVideoWidth = max(newVideoWidth, Constants.Distance.MusicMode.minWindowWidth)
    newVideoWidth = min(newVideoWidth, MiniPlayerViewController.maxWindowWidth)
    newVideoWidth = min(newVideoWidth, containerFrame.width)

    var newVideoHeight: CGFloat = 0
    if isVideoVisible {
      let videoAspect = video.videoViewAspect
      newVideoHeight = newVideoWidth / videoAspect

      if isPlaylistVisible {
        // If playlist is visible, keep the window height fixed.
        // The video will only be able to expand until the playlist is at its min height
        let minBottomBarHeight: CGFloat = Constants.Distance.MusicMode.oscHeight + Constants.Distance.MusicMode.minPlaylistHeight
        let maxVideoHeight = windowHeight - minBottomBarHeight
        if newVideoHeight > maxVideoHeight {
          newVideoHeight = maxVideoHeight
          newVideoWidth = newVideoHeight * videoAspect
        }
      }
    }

    var newOriginX = windowFrame.origin.x

    // Determine which X direction to scale towards by checking which side of the screen it's closest to
    let distanceToLeadingSideOfScreen = abs(abs(windowFrame.minX) - abs(containerFrame.minX))
    let distanceToTrailingSideOfScreen = abs(abs(windowFrame.maxX) - abs(containerFrame.maxX))
    if distanceToTrailingSideOfScreen < distanceToLeadingSideOfScreen {
      // Closer to trailing side. Keep trailing side fixed by adjusting the window origin by the width changed
      let widthChange = windowFrame.width - newVideoWidth
      newOriginX += widthChange
    }
    // else (closer to leading side): keep leading side fixed

    let newWindowOrigin = NSPoint(x: newOriginX, y: windowFrame.origin.y)
    let newWindowSize = NSSize(width: newVideoWidth, height: windowHeight)
    var newWindowFrame = NSRect(origin: newWindowOrigin, size: newWindowSize)

    if ScreenFitOption.stayInside.shouldMoveWindowToKeepInContainer {
      newWindowFrame = newWindowFrame.constrain(in: containerFrame)
    }

    return clone(windowFrame: newWindowFrame)
  }

  var description: String {
    return "MusicModeGeometry(\(screenID.quoted) \(isVideoVisible ? "videoH:\(videoHeight.strMin)" : "videoHidden") aspect:\(video.videoViewAspect.mpvAspectString) \(isPlaylistVisible ? "pListH:\(playlistHeight.strMin)" : "pListHidden") btmBarH:\(bottomBarHeight.strMin) windowFrame:\(windowFrame))"
  }

  static func playlistHeight(windowFrame: CGRect, video: VideoGeometry, isVideoVisible: Bool, isPlaylistVisible: Bool) -> CGFloat {
    guard isPlaylistVisible else {
      return 0
    }
    let videoHeight = videoHeight(windowFrame: windowFrame, video: video, isVideoVisible: isVideoVisible)
    return windowFrame.height - videoHeight - Constants.Distance.MusicMode.oscHeight
  }

  static func videoHeight(windowFrame: CGRect, video: VideoGeometry, isVideoVisible: Bool) -> CGFloat {
    guard isVideoVisible else {
      return 0
    }
    return round(windowFrame.width / video.videoViewAspect)
  }

  static func videoHeightWhenVisible(windowFrame: CGRect, video: VideoGeometry) -> CGFloat {
    return round(windowFrame.width / video.videoViewAspect)
  }

}
