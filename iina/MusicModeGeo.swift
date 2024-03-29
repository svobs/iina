//
//  MusicModeGeometry.swift
//  iina
//
//  Created by Matt Svoboda on 9/18/23.
//  Copyright © 2023 lhc. All rights reserved.
//

import Foundation

/**
 `MusicModeGeometry`
 */
struct MusicModeGeometry: Equatable, CustomStringConvertible {
  let windowFrame: NSRect
  let screenID: String
  let playlistHeight: CGFloat  /// indicates playlist height when visible, even if not currently visible
  let isVideoVisible: Bool
  let isPlaylistVisible: Bool  /// indicates if playlist is currently visible
  let videoAspect: CGFloat

  init(windowFrame: NSRect, screenID: String, playlistHeight: CGFloat, 
       isVideoVisible: Bool, isPlaylistVisible: Bool, videoAspect: CGFloat) {
    self.windowFrame = windowFrame
    self.screenID = screenID
    if isPlaylistVisible {
      /// Ignore given `playlistHeight` and calculate it from the other params
      let videoHeight = isVideoVisible ? windowFrame.width / videoAspect : 0
      let musicModeOSCHeight = Constants.Distance.MusicMode.oscHeight
      self.playlistHeight = round(windowFrame.height - musicModeOSCHeight - videoHeight)
    } else {
      /// Sometimes `playlistHeight` can fall slightly below due to rounding errors. Just correct it:
      self.playlistHeight = max(playlistHeight, Constants.Distance.MusicMode.minPlaylistHeight)
    }
    self.isVideoVisible = isVideoVisible
    self.isPlaylistVisible = isPlaylistVisible
    self.videoAspect = videoAspect
  }

  func clone(windowFrame: NSRect? = nil, screenID: String? = nil, playlistHeight: CGFloat? = nil,
             isVideoVisible: Bool? = nil, isPlaylistVisible: Bool? = nil,
             videoAspect: CGFloat? = nil) -> MusicModeGeometry {
    return MusicModeGeometry(windowFrame: windowFrame ?? self.windowFrame,
                             screenID: screenID ?? self.screenID,
                             // if playlist is visible, this will be ignored and recalculated in the constructor
                             playlistHeight: playlistHeight ?? self.playlistHeight,
                             isVideoVisible: isVideoVisible ?? self.isVideoVisible,
                             isPlaylistVisible: isPlaylistVisible ?? self.isPlaylistVisible,
                             videoAspect: videoAspect ?? self.videoAspect)
  }

  func toPWGeometry() -> PWGeometry {
    let outsideBottomBarHeight = Constants.Distance.MusicMode.oscHeight + (isPlaylistVisible ? playlistHeight : 0)
    return PWGeometry(windowFrame: windowFrame,
                           screenID: screenID,
                           fitOption: .keepInVisibleScreen,
                           mode: .musicMode,
                           topMarginHeight: 0,
                           outsideTopBarHeight: 0,
                           outsideTrailingBarWidth: 0,
                           outsideBottomBarHeight: outsideBottomBarHeight,
                           outsideLeadingBarWidth: 0,
                           insideTopBarHeight: 0,
                           insideTrailingBarWidth: 0,
                           insideBottomBarHeight: 0,
                           insideLeadingBarWidth: 0,
                           videoAspect: videoAspect)
  }

  var videoHeightIfVisible: CGFloat {
    let videoHeightByDivision = round(windowFrame.width / videoAspect)
    let otherControlsHeight = Constants.Distance.MusicMode.oscHeight + playlistHeight
    let videoHeightBySubtraction = windowFrame.height - otherControlsHeight
    // Align to other controls if within 1 px to smooth out division imprecision
    if abs(videoHeightByDivision - videoHeightBySubtraction) < 1 {
      return videoHeightBySubtraction
    }
    return videoHeightByDivision
  }

  var videoSize: NSSize? {
    guard isVideoVisible else { return nil }
    return NSSize(width: windowFrame.width, height: videoHeightIfVisible)
  }

  var viewportSize: NSSize? {
    return videoSize
  }

  var videoHeight: CGFloat {
    return isVideoVisible ? videoHeightIfVisible : 0
  }

  var bottomBarHeight: CGFloat {
    return windowFrame.height - videoHeight
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
    return "MusicModeGeometry(Video={show:\(isVideoVisible.yn) H:\(videoHeight) aspect:\(videoAspect.aspectNormalDecimalString)} PL={show:\(isPlaylistVisible.yn) H:\(playlistHeight)} BtmBarH:\(bottomBarHeight) windowFrame:\(windowFrame))"
  }
}
