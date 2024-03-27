//
//  WinGeometry.swift
//  iina
//
//  Created by Matt Svoboda on 7/11/23.
//  Copyright © 2023 lhc. All rights reserved.
//

import Foundation

/// Data structure containing size values of four sides
struct BoxQuad: Equatable {
  let top: CGFloat
  let trailing: CGFloat
  let bottom: CGFloat
  let leading: CGFloat

  var totalWidth: CGFloat {
    return leading + trailing
  }

  var totalHeight: CGFloat {
    return top + bottom
  }

  static let zero = BoxQuad(top: 0, trailing: 0, bottom: 0, leading: 0)
}

/// Describes how a given player window must fit inside its given screen.
enum ScreenFitOption: Int {

  case noConstraints = 0

  /// Constrains inside `screen.visibleFrame`
  case keepInVisibleScreen

  /// Constrains and centers inside `screen.visibleFrame`
  case centerInVisibleScreen

  /// Constrains inside `screen.frame`
  case legacyFullScreen

  /// Constrains inside `screen.frameWithoutCameraHousing`. Provided here for completeness, but not used at present.
  case nativeFullScreen

  var isFullScreen: Bool {
    switch self {
    case .legacyFullScreen, .nativeFullScreen:
      return true
    default:
      return false
    }
  }

  var shouldMoveWindowToKeepInContainer: Bool {
    switch self {
    case .legacyFullScreen, .nativeFullScreen:
      return true
    case .keepInVisibleScreen, .centerInVisibleScreen:
      return Preference.bool(for: .moveWindowIntoVisibleScreenOnResize)
    default:
      return false
    }
  }
}

/**
`WinGeometry`
 Data structure which describes the basic layout configuration of a player window (`PlayerWindowController`).

 For `let wc = PlayerWindowController()`, an instance of this class describes:
 1. The size & position (`windowFrame`) of an IINA player `NSWindow`.
 2. The size of the window's viewport (`viewportView` in a `PlayerWindowController` instance).
    The viewport contains the `videoView` and all of the `Preference.PanelPlacement.inside` views (`viewportSize`).
    Size is inferred by subtracting the bar sizes from `windowFrame`.
 3. Either the height or width of each of the 4 `outsideViewport` bars, measured as the distance between the
    outside edge of `viewportView` and the outermost edge of the bar. This is the minimum needed to determine
    its size & position; the rest can be inferred from `windowFrame` and `viewportSize`.
    If instead the bar is hidden or is shown as `insideViewport`, its outside value will be `0`.
 4. Either  height or width of each of the 4 `insideViewport` bars. These are measured from the nearest outside wall of
    `viewportView`.  If instead the bar is hidden or is shown as `outsideViewport`, its inside value will be `0`.
 5. The size of the video itself (`videoView`), which may or may not be equal to the size of `viewportView`,
    depending on whether empty space is allowed around the video.
 6. The video aspect ratio. This is stored here mainly to create a central reference for it, to avoid differing
    values which can arise if calculating it from disparate sources.

 Below is an example of a player window with letterboxed video, where the viewport is taller than `videoView`.
 • Identifiers beginning with `wc.` refer to fields in the `PlayerWindowController` instance.
 • Identifiers beginning with `geo.` are `WinGeometry` fields.
 • The window's frame (`windowFrame`) is the outermost rectangle.
 • The frame of `wc.videoView` is the innermost dotted-lined rectangle.
 • The frame of `wc.viewportView` contains `wc.videoView` and additional space for black bars.
 •
 ~
 ~                            `geo.viewportSize.width`
 ~                             (of `wc.viewportView`)
 ~                             ◄---------------►
 ┌─────────────────────────────────────────────────────────────────────────────┐`geo.windowFrame`
 │                                 ▲`geo.topMarginHeight`                      │
 │                                 ▼ (only used to cover Macbook notch)        │
 ├─────────────────────────────────────────────────────────────────────────────┤
 │                               ▲                                             │
 │                               ┊`geo.outsideTopBarHeight`                    │
 │                               ▼   (`wc.topBarView`)                         │
 ├────────────────────────────┬─────────────────┬──────────────────────────────┤ ─ ◄--- `geo.insideTopBarHeight == 0`
 │                            │black bar (empty)│                              │ ▲
 │                            ├─────────────────┤                              │ ┊ `geo.viewportSize.height`
 │◄--------------------------►│ `geo.videoSize` │◄----------------------------►│ ┊  (of `wc.viewportView`)
 │                            │(`wc.videoView`) │ `geo.outsideTrailingBarWidth`│ ┊
 │`geo.outsideLeadingBarWidth`├─────────────────┤ (of `wc.trailingSidebarView`)│ ┊
 │(of `wc.leadingSidebarView`)│black bar (empty)│                              │ ▼
 ├────────────────────────────┴─────────────────┴──────────────────────────────┤ ─ ◄--- `geo.insideBottomBarHeight == 0`
 │                                ▲                                            │
 │                                ┊`geo.outsideBottomBarHeight`                │
 │                                ▼   (of `wc.bottomBarView`)                  │
 └─────────────────────────────────────────────────────────────────────────────┘
 */
struct WinGeometry: Equatable, CustomStringConvertible {
  // MARK: - Stored properties

  // The ID of the screen on which this window is displayed
  let screenID: String
  let fitOption: ScreenFitOption
  // The mode affects lockViewportToVideo behavior and minimum sizes
  let mode: PlayerWindowMode

  /// The size & position (`window.frame`) of an IINA player `NSWindow`.
  let windowFrame: NSRect

  // Extra black space (if any) above outsideTopBar, used for covering MacBook's magic camera housing while in legacy fullscreen
  let topMarginHeight: CGFloat

  // Outside panels
  let outsideTopBarHeight: CGFloat
  let outsideTrailingBarWidth: CGFloat
  let outsideBottomBarHeight: CGFloat
  let outsideLeadingBarWidth: CGFloat

  // Inside panels
  let insideTopBarHeight: CGFloat
  let insideTrailingBarWidth: CGFloat
  let insideBottomBarHeight: CGFloat
  let insideLeadingBarWidth: CGFloat

  let viewportMargins: BoxQuad
  let videoAspect: CGFloat
  let videoSize: NSSize

  // MARK: - Initializers

  /// Derives `viewportSize` and `videoSize` from `windowFrame`, `viewportMargins` and `videoAspect`
  init(windowFrame: NSRect, screenID: String, fitOption: ScreenFitOption, mode: PlayerWindowMode, topMarginHeight: CGFloat,
       outsideTopBarHeight: CGFloat, outsideTrailingBarWidth: CGFloat, outsideBottomBarHeight: CGFloat, outsideLeadingBarWidth: CGFloat,
       insideTopBarHeight: CGFloat, insideTrailingBarWidth: CGFloat, insideBottomBarHeight: CGFloat, insideLeadingBarWidth: CGFloat,
       viewportMargins: BoxQuad? = nil, videoAspect: CGFloat) {

    self.windowFrame = windowFrame
    self.screenID = screenID
    self.fitOption = fitOption
    self.mode = mode

    assert(topMarginHeight >= 0, "Expected topMarginHeight >= 0, found \(topMarginHeight)")
    self.topMarginHeight = topMarginHeight

    assert(outsideTopBarHeight >= 0, "Expected outsideTopBarHeight >= 0, found \(outsideTopBarHeight)")
    assert(outsideTrailingBarWidth >= 0, "Expected outsideTrailingBarWidth >= 0, found \(outsideTrailingBarWidth)")
    assert(outsideBottomBarHeight >= 0, "Expected outsideBottomBarHeight >= 0, found \(outsideBottomBarHeight)")
    assert(outsideLeadingBarWidth >= 0, "Expected outsideLeadingBarWidth >= 0, found \(outsideLeadingBarWidth)")
    self.outsideTopBarHeight = outsideTopBarHeight
    self.outsideTrailingBarWidth = outsideTrailingBarWidth
    self.outsideBottomBarHeight = outsideBottomBarHeight
    self.outsideLeadingBarWidth = outsideLeadingBarWidth

    assert(insideTopBarHeight >= 0, "Expected insideTopBarHeight >= 0, found \(insideTopBarHeight)")
    assert(insideTrailingBarWidth >= 0, "Expected insideTrailingBarWidth >= 0, found \(insideTrailingBarWidth)")
    assert(insideBottomBarHeight >= 0, "Expected insideBottomBarHeight >= 0, found \(insideBottomBarHeight)")
    assert(insideLeadingBarWidth >= 0, "Expected insideLeadingBarWidth >= 0, found \(insideLeadingBarWidth)")
    self.insideTopBarHeight = insideTopBarHeight
    self.insideTrailingBarWidth = insideTrailingBarWidth
    self.insideBottomBarHeight = insideBottomBarHeight
    self.insideLeadingBarWidth = insideLeadingBarWidth

    self.videoAspect = videoAspect

    let viewportSize = WinGeometry.deriveViewportSize(from: windowFrame, topMarginHeight: topMarginHeight, outsideTopBarHeight: outsideTopBarHeight, outsideTrailingBarWidth: outsideTrailingBarWidth, outsideBottomBarHeight: outsideBottomBarHeight, outsideLeadingBarWidth: outsideLeadingBarWidth)
    let videoSize = WinGeometry.computeVideoSize(withAspectRatio: videoAspect, toFillIn: viewportSize, margins: viewportMargins, mode: mode)
    self.videoSize = videoSize
    if let viewportMargins {
      self.viewportMargins = viewportMargins
    } else {
      let insideBars = BoxQuad(top: insideTopBarHeight, trailing: insideTrailingBarWidth, bottom: insideBottomBarHeight, leading: insideLeadingBarWidth)
      self.viewportMargins = WinGeometry.computeBestViewportMargins(viewportSize: viewportSize, videoSize: videoSize, insideBars: insideBars, mode: mode)
    }

    assert(insideLeadingBarWidth >= 0, "Expected insideLeadingBarWidth >= 0, found \(insideLeadingBarWidth)")
  }

  static func fullScreenWindowFrame(in screen: NSScreen, legacy: Bool) -> NSRect {
    if legacy {
      return screen.frame
    } else {
      return screen.frameWithoutCameraHousing
    }
  }

  /// See also `LayoutState.buildFullScreenGeometry()`.
  static func forFullScreen(in screen: NSScreen, legacy: Bool, mode: PlayerWindowMode,
                            outsideTopBarHeight: CGFloat, outsideTrailingBarWidth: CGFloat,
                            outsideBottomBarHeight: CGFloat, outsideLeadingBarWidth: CGFloat,
                            insideTopBarHeight: CGFloat, insideTrailingBarWidth: CGFloat,
                            insideBottomBarHeight: CGFloat, insideLeadingBarWidth: CGFloat,
                            videoAspect: CGFloat,
                            allowVideoToOverlapCameraHousing: Bool) -> WinGeometry {

    let windowFrame = fullScreenWindowFrame(in: screen, legacy: legacy)
    let fitOption: ScreenFitOption
    let topMarginHeight: CGFloat
    if legacy {
      topMarginHeight = allowVideoToOverlapCameraHousing ? 0 : screen.cameraHousingHeight ?? 0
      fitOption = .legacyFullScreen
    } else {
      topMarginHeight = 0
      fitOption = .nativeFullScreen
    }

    return WinGeometry(windowFrame: windowFrame, screenID: screen.screenID, fitOption: fitOption,
                           mode: mode, topMarginHeight: topMarginHeight,
                           outsideTopBarHeight: outsideTopBarHeight, outsideTrailingBarWidth: outsideTrailingBarWidth,
                           outsideBottomBarHeight: outsideBottomBarHeight, outsideLeadingBarWidth: outsideLeadingBarWidth,
                           insideTopBarHeight: insideTopBarHeight, insideTrailingBarWidth: insideTrailingBarWidth,
                           insideBottomBarHeight: insideBottomBarHeight, insideLeadingBarWidth: insideLeadingBarWidth,
                           videoAspect: videoAspect)
  }

  func clone(windowFrame: NSRect? = nil, screenID: String? = nil, fitOption: ScreenFitOption? = nil,
             mode: PlayerWindowMode? = nil, topMarginHeight: CGFloat? = nil,
             outsideTopBarHeight: CGFloat? = nil, outsideTrailingBarWidth: CGFloat? = nil,
             outsideBottomBarHeight: CGFloat? = nil, outsideLeadingBarWidth: CGFloat? = nil,
             insideTopBarHeight: CGFloat? = nil, insideTrailingBarWidth: CGFloat? = nil,
             insideBottomBarHeight: CGFloat? = nil, insideLeadingBarWidth: CGFloat? = nil,
             viewportMargins: BoxQuad? = nil,
             videoAspect: CGFloat? = nil) -> WinGeometry {

    return WinGeometry(windowFrame: windowFrame ?? self.windowFrame,
                           screenID: screenID ?? self.screenID,
                           fitOption: fitOption ?? self.fitOption,
                           mode: mode ?? self.mode,
                           topMarginHeight: topMarginHeight ?? self.topMarginHeight,
                           outsideTopBarHeight: outsideTopBarHeight ?? self.outsideTopBarHeight,
                           outsideTrailingBarWidth: outsideTrailingBarWidth ?? self.outsideTrailingBarWidth,
                           outsideBottomBarHeight: outsideBottomBarHeight ?? self.outsideBottomBarHeight,
                           outsideLeadingBarWidth: outsideLeadingBarWidth ?? self.outsideLeadingBarWidth,
                           insideTopBarHeight: insideTopBarHeight ?? self.insideTopBarHeight,
                           insideTrailingBarWidth: insideTrailingBarWidth ?? self.insideTrailingBarWidth,
                           insideBottomBarHeight: insideBottomBarHeight ?? self.insideBottomBarHeight,
                           insideLeadingBarWidth: insideLeadingBarWidth ?? self.insideLeadingBarWidth,
                           viewportMargins: viewportMargins,
                           videoAspect: videoAspect ?? self.videoAspect)
  }

  // MARK: - Computed properties

  var outsideBars: BoxQuad {
    BoxQuad(top: outsideTopBarHeight, trailing: outsideTrailingBarWidth, bottom: outsideBottomBarHeight, leading: outsideLeadingBarWidth)
  }

  var insideBars: BoxQuad {
    BoxQuad(top: insideTopBarHeight, trailing: insideTrailingBarWidth, bottom: insideBottomBarHeight, leading: insideLeadingBarWidth)
  }

  var description: String {
    return "WinGeometry (screenID: \(screenID.quoted), mode: \(mode), fit: \(fitOption), topMargin: \(topMarginHeight), outsideBars: \(outsideBars), insideBars: \(insideBars), viewportMargins: \(viewportMargins), videoAspect: \(videoAspect), videoSize: \(videoSize) windowFrame: \(windowFrame))"
  }

  /// Calculated from `windowFrame`.
  /// This will be equal to `videoSize`, unless IINA is configured to allow the window to expand beyond
  /// the bounds of the video for a letterbox/pillarbox effect (separate from anything mpv includes)
  var viewportSize: NSSize {
    return NSSize(width: windowFrame.width - outsideTrailingBarWidth - outsideLeadingBarWidth,
                  height: windowFrame.height - outsideTopBarHeight - outsideBottomBarHeight)
  }

  var viewportFrameInScreenCoords: NSRect {
    let origin = CGPoint(x: windowFrame.origin.x + outsideLeadingBarWidth,
                         y: windowFrame.origin.y + outsideBottomBarHeight)
    return NSRect(origin: origin, size: viewportSize)
  }

  var videoFrameInScreenCoords: NSRect {
    let videoFrameInWindowCoords = videoFrameInWindowCoords
    let origin = CGPoint(x: windowFrame.origin.x + videoFrameInWindowCoords.origin.x,
                         y: windowFrame.origin.y + videoFrameInWindowCoords.origin.y)
    return NSRect(origin: origin, size: videoSize)
  }

  var videoFrameInWindowCoords: NSRect {
    let viewportSize = viewportSize
    assert(viewportSize.width - videoSize.width >= 0)
    assert(viewportSize.height - videoSize.height >= 0)
    let leadingBlackSpace = (viewportSize.width - videoSize.width) * 0.5
    let bottomBlackSpace = (viewportSize.height - videoSize.height) * 0.5
    let origin = CGPoint(x: outsideLeadingBarWidth + leadingBlackSpace,
                         y: outsideBottomBarHeight + bottomBlackSpace)
    return NSRect(origin: origin, size: videoSize)
  }

  var outsideBarsTotalWidth: CGFloat {
    return outsideTrailingBarWidth + outsideLeadingBarWidth
  }

  var outsideBarsTotalHeight: CGFloat {
    return outsideTopBarHeight + outsideBottomBarHeight
  }

  var outsideBarsTotalSize: NSSize {
    return NSSize(width: outsideBarsTotalWidth, height: outsideBarsTotalHeight)
  }

  static func minViewportMargins(forMode mode: PlayerWindowMode) -> BoxQuad {
    switch mode {
    case .windowedInteractive, .fullScreenInteractive:
      return Constants.InteractiveMode.viewportMargins
    default:
      return BoxQuad.zero
    }
  }

  /// Note: this does not preserve aspect ratio
  private static func minVideoWidth(forMode mode: PlayerWindowMode) -> CGFloat {
    switch mode {
    case .windowedInteractive, .fullScreenInteractive:
      return Constants.InteractiveMode.minWindowWidth - WinGeometry.minViewportMargins(forMode: mode).totalWidth
    case .musicMode:
      return Constants.Distance.MusicMode.minWindowWidth
    default:
      return AppData.minVideoSize.width
    }
  }

  /// Note: this does not preserve aspect ratio
  private static func minVideoHeight(forMode mode: PlayerWindowMode) -> CGFloat {
    switch mode {
    case .musicMode:
      return 0
    default:
      return AppData.minVideoSize.height
    }
  }

  static func computeMinVideoSize(forAspectRatio aspect: CGFloat, mode: PlayerWindowMode) -> CGSize {
    let minWidth = minVideoWidth(forMode: mode)
    let minHeight = minVideoHeight(forMode: mode)
    let size1 = NSSize(width: minWidth, height: round(minWidth / aspect))
    let size2 = NSSize(width: round(minHeight * aspect), height: minHeight)
    if size1.height >= minHeight {
      return size1
    } else {
      return size2
    }
  }

  // This also accounts for space needed by inside sidebars, if any
  func minViewportWidth(mode: PlayerWindowMode) -> CGFloat {
    return max(WinGeometry.minVideoWidth(forMode: mode) + WinGeometry.minViewportMargins(forMode: mode).totalWidth,
               insideLeadingBarWidth + insideTrailingBarWidth + Constants.Sidebar.minSpaceBetweenInsideSidebars)
  }

  func minViewportHeight(mode: PlayerWindowMode) -> CGFloat {
    return WinGeometry.minVideoHeight(forMode: mode) + WinGeometry.minViewportMargins(forMode: mode).totalHeight
  }

  func minWindowWidth(mode: PlayerWindowMode) -> CGFloat {
    return minViewportWidth(mode: mode) + outsideBarsTotalSize.width
  }

  func minWindowHeight(mode: PlayerWindowMode) -> CGFloat {
    return minViewportHeight(mode: mode) + outsideBarsTotalSize.height
  }

  func minWindowSize(mode: PlayerWindowMode) -> NSSize {
    return NSSize(width: minWindowWidth(mode: mode), height: minWindowHeight(mode: mode))
  }

  var hasTopPaddingForCameraHousing: Bool {
    return topMarginHeight > 0
  }

  // MARK: - Static Functions

  static func areEqual(windowFrame1: NSRect? = nil, windowFrame2: NSRect? = nil, videoSize1: NSSize? = nil, videoSize2: NSSize? = nil) -> Bool {
    if let windowFrame1, let windowFrame2 {
      if !windowFrame1.equalTo(windowFrame2) {
        return false
      }
    }
    if let videoSize1, let videoSize2 {
      if !(videoSize1.width == videoSize2.width && videoSize1.height == videoSize2.height) {
        return false
      }
    }
    return true
  }

  /// Returns the limiting frame for the given `fitOption`, inside which the player window must fit.
  /// If no fit needed, returns `nil`.
  static func getContainerFrame(forScreenID screenID: String, fitOption: ScreenFitOption) -> NSRect? {
    let screen = NSScreen.getScreenOrDefault(screenID: screenID)

    switch fitOption {
    case .noConstraints:
      return nil
    case .keepInVisibleScreen, .centerInVisibleScreen:
      return screen.visibleFrame
    case .legacyFullScreen:
      return screen.frame
    case .nativeFullScreen:
      return screen.frameWithoutCameraHousing
    }
  }

  static func deriveViewportSize(from windowFrame: NSRect, topMarginHeight: CGFloat,
                                 outsideTopBarHeight: CGFloat, outsideTrailingBarWidth: CGFloat,
                                 outsideBottomBarHeight: CGFloat, outsideLeadingBarWidth: CGFloat) -> NSSize {
    return NSSize(width: windowFrame.width - outsideTrailingBarWidth - outsideLeadingBarWidth,
                  height: windowFrame.height - outsideTopBarHeight - outsideBottomBarHeight - topMarginHeight)
  }

  /// Snap `value` to `otherValue` if they are less than 1 px apart. If it can't snap, the number is rounded to
  /// the nearest integer.
  ///
  /// This helps smooth out division imprecision. The goal is to end up with whole numbers in calculation results
  /// without having to distort things. Fractional values will be interpreted differently by mpv, Core Graphics,
  /// AppKit, which can ultimately result in jarring visual glitches during Core animations.
  ///
  /// It is the requestor's responsibility to ensure that `otherValue` is already an integer.
  static func snap(_ value: CGFloat, to otherValue: CGFloat) -> CGFloat {
    if abs(value - otherValue) < 1 {
      return otherValue
    } else {
      return round(value)
    }
  }

  private static func computeVideoSize(withAspectRatio videoAspect: CGFloat, toFillIn viewportSize: NSSize,
                                       margins: BoxQuad? = nil, mode: PlayerWindowMode) -> NSSize {
    if viewportSize.width == 0 || viewportSize.height == 0 {
      return NSSize.zero
    }

    let minViewportMargins = margins ?? minViewportMargins(forMode: mode)
    let usableViewportSize = NSSize(width: viewportSize.width - minViewportMargins.totalWidth,
                                    height: viewportSize.height - minViewportMargins.totalHeight)
    let videoSize: NSSize
    /// Compute `videoSize` to fit within `viewportSize` while maintaining `videoAspect`:
    if videoAspect < usableViewportSize.mpvAspect {  // video is taller, shrink to meet height
      var videoWidth = usableViewportSize.height * videoAspect
      videoWidth = snap(videoWidth, to: usableViewportSize.width)
      videoSize = NSSize(width: round(videoWidth), height: usableViewportSize.height)
    } else {  // video is wider, shrink to meet width
      var videoHeight = usableViewportSize.width / videoAspect
      videoHeight = snap(videoHeight, to: usableViewportSize.height)
      // Make sure to end up with whole numbers here! Decimal values can be interpreted differently by
      // mpv, Core Graphics, AppKit, which will cause animation glitches
      videoSize = NSSize(width: usableViewportSize.width, height: round(videoHeight))
    }

    return videoSize
  }

  static func computeBestViewportMargins(viewportSize: NSSize, videoSize: NSSize, insideBars: BoxQuad, mode: PlayerWindowMode) -> BoxQuad {
    guard viewportSize.width > 0 && viewportSize.height > 0 else {
      return BoxQuad.zero
    }
    if mode == .musicMode {
      // Viewport size is always equal to video size in music mode
      return BoxQuad.zero
    }
    var leadingMargin: CGFloat = 0
    var trailingMargin: CGFloat = 0

    var unusedWidth = max(0, viewportSize.width - videoSize.width)
    if unusedWidth > 0 {

      if mode == .fullScreen {
        leadingMargin += (unusedWidth * 0.5)
        trailingMargin += (unusedWidth * 0.5)
      } else {
        let leadingSidebarWidth = insideBars.leading
        let trailingSidebarWidth = insideBars.trailing

        let viewportMidpointX = viewportSize.width * 0.5
        let leadingVideoIdealX = viewportMidpointX - (videoSize.width * 0.5)
        let trailingVideoIdealX = viewportMidpointX + (videoSize.width * 0.5)

        let leadingSidebarClearance = leadingVideoIdealX - leadingSidebarWidth
        let trailingSidebarClearance = viewportSize.width - trailingVideoIdealX - trailingSidebarWidth
        let freeViewportWidthTotal = viewportSize.width - videoSize.width - leadingSidebarWidth - trailingSidebarWidth

        if leadingSidebarClearance >= 0 && trailingSidebarClearance >= 0 {
          // Easy case: just center the video in the viewport:
          leadingMargin += (unusedWidth * 0.5)
          trailingMargin += (unusedWidth * 0.5)
        } else if freeViewportWidthTotal >= 0 {
          // We have enough space to realign video to fit within sidebars
          leadingMargin += leadingSidebarWidth
          trailingMargin += trailingSidebarWidth
          unusedWidth = unusedWidth - leadingSidebarWidth - trailingSidebarWidth
          let leadingSidebarDeficit = leadingSidebarClearance > 0 ? 0 : -leadingSidebarClearance
          let trailingSidebarDeficit = trailingSidebarClearance > 0 ? 0 : -trailingSidebarClearance

          if trailingSidebarDeficit > 0 {
            leadingMargin += unusedWidth
          } else if leadingSidebarDeficit > 0 {
            trailingMargin += unusedWidth
          }
        } else if leadingSidebarWidth == 0 {
          // Not enough margin to fit both sidebar and video, + only trailing sidebar visible.
          // Allocate all margin to trailing sidebar
          trailingMargin += unusedWidth
        } else if trailingSidebarWidth == 0 {
          // Not enough margin to fit both sidebar and video, + only leading sidebar visible.
          // Allocate all margin to leading sidebar
          leadingMargin += unusedWidth
        } else {
          // Not enough space for everything. Just center video between sidebars
          let leadingSidebarTrailingX = leadingSidebarWidth
          let trailingSidebarLeadingX = viewportSize.width - trailingSidebarWidth
          let midpointBetweenSidebarsX = ((trailingSidebarLeadingX - leadingSidebarTrailingX) * 0.5) + leadingSidebarTrailingX
          var leadingMarginNeededToCenter = midpointBetweenSidebarsX - (videoSize.width * 0.5)
          var trailingMarginNeededToCenter = viewportSize.width - (midpointBetweenSidebarsX + (videoSize.width * 0.5))
          // Do not allow negative margins. They would cause the video to move outside the viewport bounds
          if leadingMarginNeededToCenter < 0 {
            // Give the margin back to the other sidebar
            trailingMarginNeededToCenter -= leadingMarginNeededToCenter
            leadingMarginNeededToCenter = 0
          }
          if trailingMarginNeededToCenter < 0 {
            leadingMarginNeededToCenter -= trailingMarginNeededToCenter
            trailingMarginNeededToCenter = 0
          }
          // Allocate the scarce amount of unusedWidth proportionately to the demand:
          let allocationFactor = unusedWidth / (leadingMarginNeededToCenter + trailingMarginNeededToCenter)

          leadingMargin += leadingMarginNeededToCenter * allocationFactor
          trailingMargin += trailingMarginNeededToCenter * allocationFactor
        }
      }

      // Round to integers for a smoother animation
      leadingMargin = leadingMargin.rounded(.down)
      trailingMargin = trailingMargin.rounded(.up)
    }

    if Logger.isTraceEnabled {
      let remainingWidthForVideo = viewportSize.width - (leadingMargin + trailingMargin)
      Logger.log("Viewport: Sidebars=[lead:\(insideBars.leading), trail:\(insideBars.trailing)] leadMargin: \(leadingMargin), trailMargin: \(trailingMargin), remainingWidthForVideo: \(remainingWidthForVideo), videoWidth: \(videoSize.width)")
    }
    let unusedHeight = viewportSize.height - videoSize.height
    let computedMargins = BoxQuad(top: (unusedHeight * 0.5).rounded(.down), trailing: trailingMargin,
                                  bottom: (unusedHeight * 0.5).rounded(.up), leading: leadingMargin)
    return computedMargins
  }

  // MARK: - Instance Functions

  private func getContainerFrame(fitOption: ScreenFitOption? = nil) -> NSRect? {
    return WinGeometry.getContainerFrame(forScreenID: screenID, fitOption: fitOption ?? self.fitOption)
  }

  fileprivate func computeMaxViewportSize(in containerSize: NSSize) -> NSSize {
    // Resize only the video. Panels outside the video do not change size.
    // To do this, subtract the "outside" panels from the container frame
    return NSSize(width: containerSize.width - outsideBarsTotalWidth,
                  height: containerSize.height - outsideBarsTotalHeight)
  }

  // Computes & returns the max video size with proper aspect ratio which can fit in the given container, after subtracting outside bars
  fileprivate func computeMaxVideoSize(in containerSize: NSSize) -> NSSize {
    let maxViewportSize = computeMaxViewportSize(in: containerSize)
    return WinGeometry.computeVideoSize(withAspectRatio: videoAspect, toFillIn: maxViewportSize, mode: mode)
  }

  private func adjustWindowOrigin(forNewWindowSize newWindowSize: NSSize) -> NSPoint {
    // Round the results to prevent excessive window drift due to small imprecisions in calculation
    let deltaX = (newWindowSize.width - windowFrame.size.width) / 2
    let deltaY = (newWindowSize.height - windowFrame.size.height) / 2
    return NSPoint(x: round(windowFrame.origin.x - deltaX),
                   y: round(windowFrame.origin.y - deltaY))
  }

  func refit(_ newFit: ScreenFitOption? = nil, lockViewportToVideoSize: Bool? = nil) -> WinGeometry {
    return scaleViewport(fitOption: newFit, lockViewportToVideoSize: lockViewportToVideoSize)
  }

  func hasEqual(windowFrame windowFrame2: NSRect? = nil, videoSize videoSize2: NSSize? = nil) -> Bool {
    return WinGeometry.areEqual(windowFrame1: windowFrame, windowFrame2: windowFrame2, videoSize1: videoSize, videoSize2: videoSize2)
  }

  /// Computes a new `WinGeometry`, attempting to attain the given window size.
  func scaleWindow(to desiredWindowSize: NSSize? = nil,
                   screenID: String? = nil,
                   fitOption: ScreenFitOption? = nil) -> WinGeometry {
    let requestedViewportSize: NSSize?
    if let desiredWindowSize = desiredWindowSize {
      let outsideBarsTotalSize = outsideBarsTotalSize
      requestedViewportSize = NSSize(width: desiredWindowSize.width - outsideBarsTotalSize.width,
                                     height: desiredWindowSize.height - outsideBarsTotalSize.height)
    } else {
      requestedViewportSize = nil
    }
    return scaleViewport(to: requestedViewportSize, screenID: screenID, fitOption: fitOption)
  }

  /// Computes a new `WinGeometry` from this one:
  /// • If `desiredSize` is given, the `windowFrame` will be shrunk or grown as needed, as will the `videoSize` which will
  /// be resized to fit in the new `viewportSize` based on `videoAspect`.
  /// • If `mode` is provided, it will be applied to the resulting `WinGeometry`.
  /// • If (1) `lockViewportToVideoSize` is specified, its value will be used (this should only be specified in rare cases).
  /// Otherwise (2) if `mode.alwaysLockViewportToVideoSize==true`, then `viewportSize` will be shrunk to the same size as `videoSize`,
  /// and `windowFrame` will be resized accordingly; otherwise, (3) `Preference.bool(for: .lockViewportToVideoSize)` will be used.
  /// • If `screenID` is provided, it will be associated with the resulting `WinGeometry`; otherwise `self.screenID` will be used.
  /// • If `fitOption` is provided, it will be applied to the resulting `WinGeometry`; otherwise `self.fitOption` will be used.
  func scaleViewport(to desiredSize: NSSize? = nil,
                     screenID: String? = nil,
                     fitOption: ScreenFitOption? = nil,
                     lockViewportToVideoSize: Bool? = nil,
                     mode: PlayerWindowMode? = nil) -> WinGeometry {

    // -- First, set up needed variables

    let mode = mode ?? self.mode
    let lockViewportToVideoSize = lockViewportToVideoSize ?? Preference.bool(for: .lockViewportToVideoSize) || mode.alwaysLockViewportToVideoSize
    // do not center in screen again unless explicitly requested
    let newFitOption = fitOption ?? (self.fitOption == .centerInVisibleScreen ? .keepInVisibleScreen : self.fitOption)
    let outsideBarsSize = self.outsideBarsTotalSize
    let newScreenID = screenID ?? self.screenID
    let containerFrame: NSRect? = WinGeometry.getContainerFrame(forScreenID: newScreenID, fitOption: newFitOption)
    let maxViewportSize: NSSize?
    if let containerFrame {
      maxViewportSize = computeMaxViewportSize(in: containerFrame.size)
    } else {
      maxViewportSize = nil
    }

    var newViewportSize = desiredSize ?? viewportSize
    if Logger.isTraceEnabled {
      Logger.log("[geo] ScaleViewport start, newViewportSize=\(newViewportSize), lockViewport=\(lockViewportToVideoSize.yn)", level: .verbose)
    }

    // -- Viewport size calculation

    /// Make sure viewport size is at least as large as min.
    /// This is especially important when inside sidebars are taking up most of the space & `lockViewportToVideoSize` is `true`.
    let minVideoSize = WinGeometry.computeMinVideoSize(forAspectRatio: videoAspect, mode: mode)
    newViewportSize = NSSize(width: max(minVideoSize.width, newViewportSize.width),
                             height: max(minVideoSize.height, newViewportSize.height))

    if lockViewportToVideoSize {
      if let maxViewportSize {
        /// Constrain `viewportSize` within `containerFrame`. Gotta do this BEFORE computing videoSize.
        /// So we do it again below. Big deal. Been mucking with this code way too long. It's fine.
        newViewportSize = NSSize(width: min(newViewportSize.width, maxViewportSize.width),
                                 height: min(newViewportSize.height, maxViewportSize.height))
      }

      /// Compute `videoSize` to fit within `viewportSize` (minus `viewportMargins`) while maintaining `videoAspect`:
      let newVideoSize = WinGeometry.computeVideoSize(withAspectRatio: videoAspect, toFillIn: newViewportSize, mode: mode)
      /// Remember that interactive mode has fixed nonzero viewport margins, despite `lockViewportToVideoSize==true`
      let minViewportMargins = WinGeometry.minViewportMargins(forMode: mode)
      newViewportSize = NSSize(width: newVideoSize.width + minViewportMargins.totalWidth,
                               height: newVideoSize.height + minViewportMargins.totalHeight)
    }

    let minViewportWidth = minViewportWidth(mode: mode)
    let minViewportHeight = minViewportHeight(mode: mode)
    newViewportSize = NSSize(width: max(minViewportWidth, newViewportSize.width),
                             height: max(minViewportHeight, newViewportSize.height))

    /// Constrain `viewportSize` within `containerFrame` if relevant:
    if let maxViewportSize {
      newViewportSize = NSSize(width: min(newViewportSize.width, maxViewportSize.width),
                               height: min(newViewportSize.height, maxViewportSize.height))
    }

    // -- Window size calculation

    let newWindowSize = NSSize(width: round(newViewportSize.width + outsideBarsSize.width),
                               height: round(newViewportSize.height + outsideBarsSize.height))

    let adjustedOrigin = adjustWindowOrigin(forNewWindowSize: newWindowSize)
    var newWindowFrame = NSRect(origin: adjustedOrigin, size: newWindowSize)
    if let containerFrame, newFitOption.shouldMoveWindowToKeepInContainer {
      newWindowFrame = newWindowFrame.constrain(in: containerFrame)
      if newFitOption == .centerInVisibleScreen {
        newWindowFrame = newWindowFrame.size.centeredRect(in: containerFrame)
      }
      if Logger.isTraceEnabled {
        Logger.log("[geo] ScaleViewport: constrainedIn=\(containerFrame) → windowFrame=\(newWindowFrame)",
                   level: .verbose)
      }
    } else if Logger.isTraceEnabled {
      Logger.log("[geo] ScaleViewport: → windowFrame=\(newWindowFrame)", level: .verbose)
    }

    return self.clone(windowFrame: newWindowFrame, screenID: newScreenID, fitOption: newFitOption, mode: mode)
  }

  func scaleVideo(to desiredVideoSize: NSSize,
                  screenID: String? = nil,
                  fitOption: ScreenFitOption? = nil,
                  lockViewportToVideoSize: Bool? = nil,
                  mode: PlayerWindowMode? = nil) -> WinGeometry {

    let mode = mode ?? self.mode
    let lockViewportToVideoSize = lockViewportToVideoSize ?? Preference.bool(for: .lockViewportToVideoSize) || mode.alwaysLockViewportToVideoSize
    if Logger.isTraceEnabled {
      Logger.log("[geo] ScaleVideo start, desiredVideoSize: \(desiredVideoSize), videoAspect: \(videoAspect), lockViewportToVideoSize: \(lockViewportToVideoSize)", level: .debug)
    }

    // do not center in screen again unless explicitly requested
    var newFitOption = fitOption ?? (self.fitOption == .centerInVisibleScreen ? .keepInVisibleScreen : self.fitOption)
    if newFitOption == .legacyFullScreen || newFitOption == .nativeFullScreen {
      // Programmer screwed up
      Logger.log("[geo] ScaleVideo: invalid fit option: \(newFitOption). Defaulting to 'none'", level: .error)
      newFitOption = .noConstraints
    }
    let newScreenID = screenID ?? self.screenID
    let containerFrame: NSRect? = WinGeometry.getContainerFrame(forScreenID: newScreenID, fitOption: newFitOption)

    var newVideoSize = desiredVideoSize

    let minVideoSize = WinGeometry.computeMinVideoSize(forAspectRatio: videoAspect, mode: mode)
    let newWidth = max(minVideoSize.width, desiredVideoSize.width)
    /// Enforce `videoView` aspectRatio: Recalculate height using width
    newVideoSize = NSSize(width: newWidth, height: round(newWidth / videoAspect))

    if let containerFrame {
      // Scale down to fit in bounds of container
      if newVideoSize.width > containerFrame.width {
        newVideoSize = NSSize(width: containerFrame.width, height: round(containerFrame.width / videoAspect))
      }

      if newVideoSize.height > containerFrame.height {
        newVideoSize = NSSize(width: round(containerFrame.height * videoAspect), height: containerFrame.height)
      }
    }

    let minViewportMargins = WinGeometry.minViewportMargins(forMode: mode)
    let newViewportSize: NSSize
    if lockViewportToVideoSize {
      /// Use `videoSize` for `desiredViewportSize`:
      newViewportSize = NSSize(width: newVideoSize.width + minViewportMargins.totalWidth,
                               height: newVideoSize.height + minViewportMargins.totalHeight)
    } else {
      // Scale existing viewport
      let scaleRatio = newVideoSize.width / videoSize.width
      let viewportSizeWithoutMinMargins = NSSize(width: viewportSize.width - minViewportMargins.totalWidth,
                                                 height: viewportSize.height - minViewportMargins.totalHeight)
      let scaledViewportWithoutMargins = viewportSizeWithoutMinMargins.multiply(scaleRatio)
      newViewportSize = NSSize(width: scaledViewportWithoutMargins.width + minViewportMargins.totalWidth,
                               height: scaledViewportWithoutMargins.height + minViewportMargins.totalHeight)
    }

    return scaleViewport(to: newViewportSize, screenID: screenID, fitOption: fitOption, mode: mode)
  }

  // Resizes the window appropriately
  func withResizedOutsideBars(newOutsideTopBarHeight: CGFloat? = nil, newOutsideTrailingBarWidth: CGFloat? = nil,
                              newOutsideBottomBarHeight: CGFloat? = nil, newOutsideLeadingBarWidth: CGFloat? = nil) -> WinGeometry {
    assert((newOutsideTopBarHeight ?? 0) >= 0)
    assert((newOutsideTrailingBarWidth ?? 0) >= 0)
    assert((newOutsideBottomBarHeight ?? 0) >= 0)
    assert((newOutsideLeadingBarWidth ?? 0) >= 0)

    var ΔW: CGFloat = 0
    var ΔH: CGFloat = 0
    var ΔX: CGFloat = 0
    var ΔY: CGFloat = 0
    if let newOutsideTopBarHeight {
      let ΔTop = newOutsideTopBarHeight - self.outsideTopBarHeight
      ΔH += ΔTop
    }
    if let newOutsideTrailingBarWidth {
      let ΔRight = newOutsideTrailingBarWidth - self.outsideTrailingBarWidth
      ΔW += ΔRight
    }
    if let newOutsideBottomBarHeight {
      let ΔBottom = newOutsideBottomBarHeight - self.outsideBottomBarHeight
      ΔH += ΔBottom
      ΔY -= ΔBottom
    }
    if let newOutsideLeadingBarWidth {
      let ΔLeft = newOutsideLeadingBarWidth - self.outsideLeadingBarWidth
      ΔW += ΔLeft
      ΔX -= ΔLeft
    }

    let newWindowFrame = CGRect(x: windowFrame.origin.x + ΔX,
                                y: windowFrame.origin.y + ΔY,
                                width: windowFrame.width + ΔW,
                                height: windowFrame.height + ΔH)
    return self.clone(windowFrame: newWindowFrame,
                      outsideTopBarHeight: newOutsideTopBarHeight, outsideTrailingBarWidth: newOutsideTrailingBarWidth,
                      outsideBottomBarHeight: newOutsideBottomBarHeight, outsideLeadingBarWidth: newOutsideLeadingBarWidth)
  }

  func withResizedBars(fitOption: ScreenFitOption? = nil,
                       outsideTopBarHeight: CGFloat? = nil, outsideTrailingBarWidth: CGFloat? = nil,
                       outsideBottomBarHeight: CGFloat? = nil, outsideLeadingBarWidth: CGFloat? = nil,
                       insideTopBarHeight: CGFloat? = nil, insideTrailingBarWidth: CGFloat? = nil,
                       insideBottomBarHeight: CGFloat? = nil, insideLeadingBarWidth: CGFloat? = nil,
                       videoAspect: CGFloat? = nil) -> WinGeometry {

    // Inside bars
    var newGeo = clone(fitOption: fitOption,
                       insideTopBarHeight: insideTopBarHeight,
                       insideTrailingBarWidth: insideTrailingBarWidth,
                       insideBottomBarHeight: insideBottomBarHeight,
                       insideLeadingBarWidth: insideLeadingBarWidth,
                       videoAspect: videoAspect)

    newGeo = newGeo.withResizedOutsideBars(newOutsideTopBarHeight: outsideTopBarHeight,
                                           newOutsideTrailingBarWidth: outsideTrailingBarWidth,
                                           newOutsideBottomBarHeight: outsideBottomBarHeight,
                                           newOutsideLeadingBarWidth: outsideLeadingBarWidth)
    return newGeo.scaleViewport()
  }

  /** Calculate the window frame from a parsed struct of mpv's `geometry` option. */
  func apply(mpvGeometry: MPVGeometryDef, desiredWindowSize: NSSize) -> WinGeometry {
    guard let screenFrame: NSRect = getContainerFrame() else {
      Logger.log("Cannot apply mpv geometry: no container frame found (fitOption: \(fitOption))", level: .error)
      return self
    }
    let maxWindowSize = screenFrame.size
    let minWindowSize = minWindowSize(mode: .windowed)

    var newWindowSize = desiredWindowSize
    var isWidthSet = false
    var isHeightSet = false
    var isXSet = false
    var isYSet = false

    if let strw = mpvGeometry.w, let wInt = Int(strw), wInt > 0 {
      var w = CGFloat(wInt)
      if mpvGeometry.wIsPercentage {
        w = w * 0.01 * Double(maxWindowSize.width)
      }
      newWindowSize.width = max(minWindowSize.width, w)
      isWidthSet = true
    }

    if let strh = mpvGeometry.h, let hInt = Int(strh), hInt > 0 {
      var h = CGFloat(hInt)
      if mpvGeometry.hIsPercentage {
        h = h * 0.01 * Double(maxWindowSize.height)
      }
      newWindowSize.height = max(minWindowSize.height, h)
      isHeightSet = true
    }

    // 1. If both width & height are set, video will scale to fit inside it, but there may be empty margins.
    // 2. If only width or height is set, but not both: derive the other from the aspect ratio.
    // 3. Otherwise default to desiredVideoSize.
    if isWidthSet && !isHeightSet {
      // Calculate height based on width and aspect
      let newViewportWidth = newWindowSize.width - outsideBarsTotalWidth
      let newViewportHeight = round(newViewportWidth / videoAspect)
      newWindowSize.height = newViewportHeight + outsideBarsTotalHeight

      var mustRecomputeWidth = false
      if newWindowSize.height > maxWindowSize.height {
        // Shrink if exceeded max height
        newWindowSize.height = maxWindowSize.height
        mustRecomputeWidth = true
      } else if newWindowSize.height < minWindowSize.height {
        newWindowSize.height = minWindowSize.height
        mustRecomputeWidth = true
      }
      if mustRecomputeWidth {
        // Recalculate width based on height and aspect
        let newViewportHeight = newWindowSize.height - outsideBarsTotalHeight
        let newViewportWidth = round(newViewportHeight * videoAspect)
        newWindowSize.width = newViewportWidth + outsideBarsTotalWidth
      }
    } else if !isWidthSet && isHeightSet {
      // Calculate width based on height and aspect
      let newViewportHeight = newWindowSize.height - outsideBarsTotalHeight
      let newViewportWidth = round(newViewportHeight * videoAspect)
      newWindowSize.width = newViewportWidth + outsideBarsTotalWidth

      var mustRecomputeHeight = false
      if newWindowSize.width > maxWindowSize.width {
        // Shrink if exceeded max width
        newWindowSize.width = maxWindowSize.width
        mustRecomputeHeight = true
      } else if newWindowSize.width < minWindowSize.width {
        newWindowSize.width = minWindowSize.width
        mustRecomputeHeight = true
      }
      if mustRecomputeHeight {
        // Recalculate height based on width and aspect
        let newViewportWidth = newWindowSize.width - outsideBarsTotalWidth
        let newViewportHeight = round(newViewportWidth / videoAspect)
        newWindowSize.height = newViewportHeight + outsideBarsTotalHeight
      }
    }

    var newOrigin = screenFrame.origin
    // x
    if let strx = mpvGeometry.x, let xInt = Int(strx), let xSign = mpvGeometry.xSign {
      let unusedScreenWidth = max(0, screenFrame.width - newWindowSize.width)
      var xOffset = CGFloat(xInt)
      if mpvGeometry.xIsPercentage {
        xOffset = xOffset * 0.01 * Double(screenFrame.width)
      }
      // Reduce/eliminate offset if not enough space on screen
      xOffset = min(unusedScreenWidth, xOffset)
      // If xSign == "-", interpret as offset of right side of window from right side of screen
      if xSign == "-" {  // Offset from RIGHT
        newOrigin.x += (screenFrame.width - newWindowSize.width)
        newOrigin.x -= xOffset
      } else {  // Offset from LEFT
        newOrigin.x += xOffset
      }
      isXSet = true
    }

    // y
    if let stry = mpvGeometry.y, let yInt = Int(stry), let ySign = mpvGeometry.ySign {
      let unusedScreenHeight = max(0, screenFrame.height - newWindowSize.height)
      var yOffset = CGFloat(yInt)
      if mpvGeometry.yIsPercentage {
        yOffset = yOffset * 0.01 * Double(screenFrame.height)
      }
      // Reduce/eliminate offset if not enough space on screen
      yOffset = min(unusedScreenHeight, yOffset)

      if ySign == "-" {  // Offset from BOTTOM
        newOrigin.y += yOffset
      } else {  // Offset from TOP
        newOrigin.y += (screenFrame.height - newWindowSize.height)
        newOrigin.y -= yOffset
      }
      isYSet = true
    }

    // If X or Y are not set, just adjust the previous values according to the change in window width or height, respectively
    let adjustedOrigin = adjustWindowOrigin(forNewWindowSize: newWindowSize)
    if !isXSet {
      newOrigin.x = adjustedOrigin.x
    }
    if !isYSet {
      newOrigin.y = adjustedOrigin.y
    }

    let newWindowFrame = NSRect(origin: newOrigin, size: newWindowSize)
    Logger.log("Calculated windowFrame from mpv geometry: \(newWindowFrame)", level: .debug)
    return self.clone(windowFrame: newWindowFrame)
  }

  // MARK: Interactive mode

  // Transition windowed mode geometry to Interactive Mode geometry. Note that this is not a direct conversion; it will modify the view sizes
  func toInteractiveMode() -> WinGeometry {
    assert(fitOption != .legacyFullScreen && fitOption != .nativeFullScreen)
    assert(mode == .windowed)
    let newMode = PlayerWindowMode.windowedInteractive
    // Close sidebars. Top and bottom bars are resized for interactive mode controls
    let newGeo = withResizedOutsideBars(newOutsideTopBarHeight: Constants.InteractiveMode.outsideTopBarHeight,
                                        newOutsideTrailingBarWidth: 0,
                                        newOutsideBottomBarHeight: Constants.InteractiveMode.outsideBottomBarHeight,
                                        newOutsideLeadingBarWidth: 0)

    // Desired viewport is current one but shrunk with fixed margin around video
    var newVideoSize = WinGeometry.computeVideoSize(withAspectRatio: videoAspect, toFillIn: viewportSize, mode: newMode)
    let viewportMargins = Constants.InteractiveMode.viewportMargins

    // Enforce min width for interactive mode window
    let minVideoWidth = WinGeometry.minVideoWidth(forMode: newMode)
    if newVideoSize.width < minVideoWidth {
      newVideoSize = NSSize(width: minVideoWidth, height: round(minVideoWidth / videoAspect))
    }

    let desiredViewportSize = NSSize(width: newVideoSize.width + viewportMargins.totalWidth,
                                     height: newVideoSize.height + viewportMargins.totalHeight)
    // This will constrain in screen
    return newGeo.clone(insideTopBarHeight: 0, insideTrailingBarWidth: 0,
                        insideBottomBarHeight: 0, insideLeadingBarWidth: 0,
                        viewportMargins: viewportMargins).scaleViewport(to: desiredViewportSize, mode: newMode)
  }

  /// Here, `videoSizeUnscaled` and `cropbox` must be the same scale, which may be different than `self.videoSize`.
  /// The cropbox is the section of the video rect which remains after the crop. Its origin is the lower left of the video.
  func cropVideo(from videoSizeOrig: NSSize, to cropbox: NSRect) -> WinGeometry {
    // First scale the cropbox to the current window scale
    let scaleRatio = videoSize.width / videoSizeOrig.width
    let cropboxScaled = NSRect(x: cropbox.origin.x * scaleRatio,
                               y: cropbox.origin.y * scaleRatio,
                               width: cropbox.width * scaleRatio,
                               height: cropbox.height * scaleRatio)

    if cropboxScaled.origin.x > videoSize.width || cropboxScaled.origin.y > videoSize.height {
      Logger.log("[geo] Cannot crop video: the cropbox is completely outside the video! CropboxScaled: \(cropboxScaled), videoSize: \(videoSize)", level: .error)
      return self
    }

    Logger.log("[geo] Cropping from cropbox: \(cropbox), scaled: \(scaleRatio)x -> \(cropboxScaled)")

    let widthRemoved = videoSize.width - cropboxScaled.width
    let heightRemoved = videoSize.height - cropboxScaled.height
    let newWindowFrame = NSRect(x: round(windowFrame.origin.x + cropboxScaled.origin.x),
                                y: round(windowFrame.origin.y + cropboxScaled.origin.y),
                                width: round(windowFrame.width - widthRemoved),
                                height: round(windowFrame.height - heightRemoved))

    let newVideoAspect = cropbox.size.mpvAspect

    let newFitOption = self.fitOption == .centerInVisibleScreen ? .keepInVisibleScreen : self.fitOption
    Logger.log("[geo] Cropped to new windowFrame: \(newWindowFrame), videoAspect: \(newVideoAspect), screenID: \(screenID), fitOption: \(newFitOption)")
    return self.clone(windowFrame: newWindowFrame, fitOption: newFitOption, videoAspect: newVideoAspect)
  }

  func uncropVideo(videoSizeOrig: NSSize, cropbox: NSRect, videoScale: CGFloat) -> WinGeometry {
    let cropboxScaled = NSRect(x: cropbox.origin.x * videoScale,
                               y: cropbox.origin.y * videoScale,
                               width: cropbox.width * videoScale,
                               height: cropbox.height * videoScale)
    // Figure out part which wasn't cropped:
    let antiCropboxSizeScaled = NSSize(width: (videoSizeOrig.width - cropbox.width) * videoScale,
                                       height: (videoSizeOrig.height - cropbox.height) * videoScale)
    let newVideoAspect = videoSizeOrig.mpvAspect
    let newWindowFrame = NSRect(x: round(windowFrame.origin.x - cropboxScaled.origin.x),
                                y: round(windowFrame.origin.y - cropboxScaled.origin.y),
                                width: round(windowFrame.width + antiCropboxSizeScaled.width),
                                height: round(windowFrame.height + antiCropboxSizeScaled.height))
    return self.clone(windowFrame: newWindowFrame, videoAspect: newVideoAspect).refit()
  }
}
