//
//  MusicModeGeometry.swift
//  iina
//
//  Created by Matt Svoboda on 9/18/23.
//  Copyright © 2023 lhc. All rights reserved.
//

import Foundation

/**
 `MusicModeGeometry`: like `PWGeometry`, but for music mode.

 Because the music mode window reuses the existing player window, it:
 * Uses the viewport to display video or album art, but can be turned off, in which case it is given a height of zero. The viewport has 0 margins on all sides when in music mode.
 * Uses the outside bottom bar for:
 * 1. Either current media info, or OSC on hover. This is always displayed in music mode and has constant height.
 * 2. Playlist if shown. Playlist has 0 height if hidden, otherwise is bounded by `minPlaylistHeight` and remaining height on screen.
 *  Never has any inside bars, outside sidebars or top bar (the views exist but are reduced to zero area).

 A `MusicModeGeometry` object can be converted to a `PWGeometry` via its `toPWGeometry()` function.
 */
struct MusicModeGeometry: Equatable, CustomStringConvertible {
  let windowFrame: NSRect
  let screenID: String
  let isVideoVisible: Bool
  let videoAspect: CGFloat

  /// indicates if playlist is currently visible
  var isPlaylistVisible: Bool {
    return playlistHeight > 0
  }

  /// indicates playlist height when visible, even if not currently visible
  var playlistHeight: CGFloat {
    return round(windowFrame.height - videoHeight - Constants.Distance.MusicMode.oscHeight)
  }

  var videoHeightIfVisible: CGFloat {
    return MusicModeGeometry.videoHeightIfVisible(windowFrame: windowFrame, videoAspect: videoAspect)
  }

  var videoHeight: CGFloat {
    return isVideoVisible ? videoHeightIfVisible : 0
  }

  var videoSize: NSSize? {
    guard isVideoVisible else { return nil }
    return NSSize(width: windowFrame.width, height: videoHeightIfVisible)
  }

  var viewportSize: NSSize? {
    return videoSize
  }

  var bottomBarHeight: CGFloat {
    return windowFrame.height - videoHeight
  }

  init(windowFrame: NSRect, screenID: String, videoAspect: CGFloat, isVideoVisible: Bool, isPlaylistVisible: Bool) {
    var windowFrame = windowFrame
    let videoHeight = MusicModeGeometry.videoHeight(windowFrame: windowFrame, videoAspect: videoAspect, isVideoVisible: isVideoVisible)
    let playlistHeight = windowFrame.height - videoHeight - Constants.Distance.MusicMode.oscHeight

    let extraWidthNeeded = Constants.Distance.MusicMode.minWindowWidth - windowFrame.width
    if extraWidthNeeded > 0 {
      if Logger.isTraceEnabled {
        Logger.log("MusicModeGeoInit: width too small; adding: \(extraWidthNeeded)")
      }
      windowFrame = NSRect(origin: windowFrame.origin, size: CGSize(width: windowFrame.width + extraWidthNeeded, height: windowFrame.height))
    }

    if isPlaylistVisible {
      let extraHeightNeeded = Constants.Distance.MusicMode.minPlaylistHeight - playlistHeight
      if extraHeightNeeded > 0 {
        if Logger.isTraceEnabled {
          Logger.log("MusicModeGeoInit: height too small for playlist; adding: \(extraHeightNeeded)")
        }
        windowFrame = NSRect(x: windowFrame.origin.x, y: windowFrame.origin.y - extraHeightNeeded,
                             width: windowFrame.width, height: windowFrame.height + extraHeightNeeded)
      }
    } else {
      let extraHeightNeeded = -playlistHeight
      if extraHeightNeeded != 0 {
        if Logger.isTraceEnabled {
          Logger.log("MusicModeGeoInit: height is invalid; adding: \(extraHeightNeeded)")
        }
        windowFrame = NSRect(x: windowFrame.origin.x, y: windowFrame.origin.y - extraHeightNeeded,
                             width: windowFrame.width, height: windowFrame.height + extraHeightNeeded)
      }
    }
    self.windowFrame = windowFrame
    self.screenID = screenID
    self.isVideoVisible = isVideoVisible
    self.videoAspect = videoAspect
    assert(isPlaylistVisible ? (self.playlistHeight >= Constants.Distance.MusicMode.minPlaylistHeight) : (self.playlistHeight == 0),
           "Playlist height invalid: isPlaylistVisible==\(isPlaylistVisible.yn) but playlistHeight==\(self.playlistHeight) < min (\(Constants.Distance.MusicMode.minPlaylistHeight))")
  }

  func clone(windowFrame: NSRect? = nil, screenID: String? = nil, videoAspect: CGFloat? = nil,
             isVideoVisible: Bool? = nil, isPlaylistVisible: Bool? = nil) -> MusicModeGeometry {
    return MusicModeGeometry(windowFrame: windowFrame ?? self.windowFrame,
                             screenID: screenID ?? self.screenID,
                             videoAspect: videoAspect ?? self.videoAspect,
                             isVideoVisible: isVideoVisible ?? self.isVideoVisible,
                             isPlaylistVisible: isPlaylistVisible ?? self.isPlaylistVisible)
  }

  /// Converts this `MusicModeGeometry` to an equivalent `PWGeometry` object.
  func toPWGeometry() -> PWGeometry {
    return PWGeometry(windowFrame: windowFrame,
                      screenID: screenID,
                      fitOption: .keepInVisibleScreen,
                      mode: .musicMode,
                      topMarginHeight: 0,
                      outsideTopBarHeight: 0,
                      outsideTrailingBarWidth: 0,
                      outsideBottomBarHeight: Constants.Distance.MusicMode.oscHeight + playlistHeight,
                      outsideLeadingBarWidth: 0,
                      insideTopBarHeight: 0,
                      insideTrailingBarWidth: 0,
                      insideBottomBarHeight: 0,
                      insideLeadingBarWidth: 0,
                      videoAspect: videoAspect)
  }

  func hasEqual(windowFrame windowFrame2: NSRect? = nil, videoSize videoSize2: NSSize? = nil) -> Bool {
    return PWGeometry.areEqual(windowFrame1: windowFrame, windowFrame2: windowFrame2, videoSize1: videoSize, videoSize2: videoSize2)
  }

  func withVideoViewVisible(_ visible: Bool) -> MusicModeGeometry {
    var newWindowFrame = windowFrame
    if visible {
      newWindowFrame.size.height += videoHeightIfVisible
    } else {
      // If playlist is also hidden, do not try to shrink smaller than the control view, which would cause
      // a constraint violation. This is possible due to small imprecisions in various layout calculations.
      newWindowFrame.size.height = max(Constants.Distance.MusicMode.oscHeight, newWindowFrame.size.height - videoHeightIfVisible)
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
    let containerFrame = PWGeometry.getContainerFrame(forScreenID: screenID, fitOption: .keepInVisibleScreen)!

    /// When the window's width changes, the video scales to match while keeping its aspect ratio,
    /// and the control bar (`musicModeControlBarView`) and playlist are pushed down.
    /// Calculate the maximum width/height the art can grow to so that `musicModeControlBarView` is not pushed off the screen.
    let minPlaylistHeight = isPlaylistVisible ? Constants.Distance.MusicMode.minPlaylistHeight : 0

    var maxWidth: CGFloat
    if isVideoVisible {
      var maxVideoHeight = containerFrame.height - Constants.Distance.MusicMode.oscHeight - minPlaylistHeight
      /// `maxVideoHeight` can be negative if very short screen! Fall back to height based on `MiniPlayerMinWidth` if needed
      maxVideoHeight = max(maxVideoHeight, round(Constants.Distance.MusicMode.minWindowWidth / videoAspect))
      maxWidth = round(maxVideoHeight * videoAspect)
    } else {
      maxWidth = MiniPlayerController.maxWindowWidth
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
    if ScreenFitOption.keepInVisibleScreen.shouldMoveWindowToKeepInContainer {
      newWindowFrame = newWindowFrame.constrain(in: containerFrame)
    }
    let fittedGeo = self.clone(windowFrame: newWindowFrame)
    Logger.log("Refitted \(fittedGeo), from requestedSize: \(requestedSize)", level: .verbose)
    return fittedGeo
  }

  func scaleVideo(to desiredSize: NSSize? = nil,
                     screenID: String? = nil) -> MusicModeGeometry? {

    guard isVideoVisible else {
      Logger.log("Cannot scale video of MusicMode: isVideoVisible=\(isVideoVisible.yesno)", level: .error)
      return nil
    }

    let newVideoSize = desiredSize ?? videoSize!
    Logger.log("Scaling MusicMode video to desiredSize: \(newVideoSize)", level: .verbose)

    let newScreenID = screenID ?? self.screenID
    let containerFrame: NSRect = PWGeometry.getContainerFrame(forScreenID: newScreenID, fitOption: .keepInVisibleScreen)!

    // Window height should not change. Only video size should be scaled
    let windowHeight = min(containerFrame.height, windowFrame.height)

    // Constrain desired width within min and max allowed, then recalculate height from new value
    var newVideoWidth = newVideoSize.width
    newVideoWidth = max(newVideoWidth, Constants.Distance.MusicMode.minWindowWidth)
    newVideoWidth = min(newVideoWidth, MiniPlayerController.maxWindowWidth)
    newVideoWidth = min(newVideoWidth, containerFrame.width)

    var newVideoHeight = newVideoWidth / videoAspect

    let minPlaylistHeight: CGFloat = isPlaylistVisible ? Constants.Distance.MusicMode.minPlaylistHeight : 0
    let minBottomBarHeight: CGFloat = Constants.Distance.MusicMode.oscHeight + minPlaylistHeight
    let maxVideoHeight = windowHeight - minBottomBarHeight
    if newVideoHeight > maxVideoHeight {
      newVideoHeight = maxVideoHeight
      newVideoWidth = newVideoHeight * videoAspect
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

    if ScreenFitOption.keepInVisibleScreen.shouldMoveWindowToKeepInContainer {
      newWindowFrame = newWindowFrame.constrain(in: containerFrame)
    }

    return clone(windowFrame: newWindowFrame)
  }

  var description: String {
    return "MusicModeGeometry(video={show:\(isVideoVisible.yn) H:\(videoHeight.strMin) aspect:\(videoAspect.aspectNormalDecimalString)} PL={show:\(isPlaylistVisible.yn) H:\(playlistHeight.strMin)} BtmBarH:\(bottomBarHeight.strMin) windowFrame:\(windowFrame))"
  }

  static func playlistHeight(windowFrame: CGRect, videoAspect: CGFloat, isVideoVisible: Bool, isPlaylistVisible: Bool) -> CGFloat {
    guard isPlaylistVisible else {
      return 0
    }
    let videoHeight = videoHeight(windowFrame: windowFrame, videoAspect: videoAspect, isVideoVisible: isVideoVisible)
    return windowFrame.height - videoHeight - Constants.Distance.MusicMode.oscHeight
  }

  static func videoHeight(windowFrame: CGRect, videoAspect: CGFloat, isVideoVisible: Bool) -> CGFloat {
    guard isVideoVisible else {
      return 0
    }
    return round(windowFrame.width / videoAspect)
  }

  static func videoHeightIfVisible(windowFrame: CGRect, videoAspect: CGFloat) -> CGFloat {
    return round(windowFrame.width / videoAspect)
  }

}
