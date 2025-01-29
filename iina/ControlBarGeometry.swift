//
//  ControlBarGeometry.swift
//  iina
//
//  Created by Matt Svoboda on 2024/09/08.
//

import Foundation

fileprivate let minTicks: Int = 0
fileprivate let maxTicks: Int = 4

fileprivate let iconSizeBaseMultiplier: CGFloat = 0.5
fileprivate let playIconSpacingScaleMultiplier: CGFloat = 0.5
fileprivate let playIconSpacingMinScaleMultiplier: CGFloat = 0.1
fileprivate let toolSpacingScaleMultiplier: CGFloat = 0.5

fileprivate let minToolBtnHeight: CGFloat = 8
fileprivate let minPlayBtnHeight: CGFloat = 8

fileprivate let floatingToolbarIconSize: CGFloat = 14
fileprivate let floatingToolbarIconSpacing: CGFloat = 5
fileprivate let floatingPlayIconSize: CGFloat = 24
fileprivate let floatingPlayIconSpacing: CGFloat = 24
fileprivate let floatingVolumeIconSize: CGFloat = 18

fileprivate let musicModeBarHeight: CGFloat = 48
fileprivate let musicModePlayIconSize: CGFloat = 24
fileprivate let musicModePlayIconSpacing: CGFloat = 16
fileprivate let musicModeToolbarIconSize: CGFloat = 14
fileprivate let musicModeToolbarIconSpacing: CGFloat = 12

fileprivate let stepIconScaleFactor: CGFloat = 0.85
fileprivate let systemArrowSymbolScaleFactor: CGFloat = 0.85

// TODO: reimplement OSC title bar feature

struct ControlBarGeometry {
  // MARK: Stored properties

  let mode: PlayerWindowMode
  let position: Preference.OSCPosition

  let arrowButtonAction: Preference.ArrowButtonAction
  /// If true, always use single-line style OSC, even if qualifying for multi-line OSC.
  ///
  /// (Only applies to top & bottom OSCs).
  let forceSingleLineStyle: Bool

  /// Preferred height for "full-width" OSCs (i.e. top or bottom, not floating or music mode)
  let barHeight: CGFloat

  /// Needed if using "multiLine" style OSC; otherwise same as `barHeight`
  let fullIconHeight: CGFloat

  let playIconSizeTicks: Int
  let playIconSpacingTicks: Int
  let toolIconSizeTicks: Int
  let toolIconSpacingTicks: Int

  let toolIconSize: CGFloat
  let toolIconSpacing: CGFloat

  /// Size of a side the 3 square playback button icons (Play/Pause, LeftArrow, RightArrow):
  let playIconSize: CGFloat

  let leftArrowImage: NSImage
  let rightArrowImage: NSImage

  /// This is usually the same as `playIconSize`, but can vary based on icon type
  let arrowIconHeight: CGFloat

  /// Depends on `arrowIconHeight` and aspect ratio of arrow image
  let arrowIconWidth: CGFloat

  /// Scale of spacing to the left & right of each playback button (for top/bottom OSC):
  let playIconSpacing: CGFloat

  let toolbarItems: [Preference.ToolBarButton]

  // MARK: Init

  /// All fields are optional. Any omitted fields will be filled in from preferences
  init(mode: PlayerWindowMode,
       oscPosition: Preference.OSCPosition? = nil,
       toolbarItems: [Preference.ToolBarButton]? = nil,
       arrowButtonAction: Preference.ArrowButtonAction? = nil,
       barHeight desiredBarHeight: CGFloat? = nil,
       forceSingleLineStyle: Bool? = nil,
       toolIconSizeTicks: Int? = nil, toolIconSpacingTicks: Int? = nil,
       playIconSizeTicks: Int? = nil, playIconSpacingTicks: Int? = nil) {
    self.mode = mode
    self.toolbarItems = toolbarItems ?? ControlBarGeometry.oscToolbarItems
    let forceSingleLineStyle = forceSingleLineStyle ?? Preference.bool(for: .oscForceSingleLine)
    self.forceSingleLineStyle = forceSingleLineStyle

    // Actual cardinal sizes should be downstream from tick values
    let playIconSizeTicks = playIconSizeTicks ?? Preference.integer(for: .oscBarPlayIconSizeTicks)
    self.playIconSizeTicks = playIconSizeTicks
    let playIconSpacingTicks = playIconSpacingTicks ?? Preference.integer(for: .oscBarPlayIconSpacingTicks)
    self.playIconSpacingTicks = playIconSpacingTicks
    let toolIconSizeTicks = toolIconSizeTicks ?? Preference.integer(for: .oscBarToolIconSizeTicks)
    self.toolIconSizeTicks = toolIconSizeTicks
    let toolIconSpacingTicks = toolIconSpacingTicks ?? Preference.integer(for: .oscBarToolIconSpacingTicks)
    self.toolIconSpacingTicks = toolIconSpacingTicks

    let oscPosition = oscPosition ?? Preference.enum(for: .oscPosition)

    let barHeight: CGFloat
    let fullIconHeight: CGFloat
    if mode == .musicMode {
      barHeight = musicModeBarHeight
      fullIconHeight = barHeight
      self.playSliderHeight = Constants.Distance.MusicMode.positionSliderWrapperViewHeight - 4
      self.playIconSize = musicModePlayIconSize
      self.toolIconSize = musicModeToolbarIconSize
      self.toolIconSpacing = musicModeToolbarIconSpacing
      self.playIconSpacing = musicModePlayIconSpacing

    } else if oscPosition == .floating {
      barHeight = 67  // not really useful here anyway
      fullIconHeight = barHeight
      self.playSliderHeight = barHeight
      self.toolIconSize = floatingToolbarIconSize
      self.toolIconSpacing = floatingToolbarIconSpacing
      self.playIconSize = floatingPlayIconSize
      self.playIconSpacing = floatingPlayIconSpacing

    } else {
      // First establish bar height
      let desiredBarHeight = desiredBarHeight ?? CGFloat(Preference.integer(for: .oscBarHeight))
      barHeight = desiredBarHeight.clamped(to: Constants.Distance.minOSCBarHeight...Constants.Distance.maxOSCBarHeight)

      if !forceSingleLineStyle && ControlBarGeometry.canUseMultiLineOSC(barHeight: barHeight, oscPosition) {
        // Is multi-line OSC
        let playSliderHeight = min(barHeight * 0.5, Constants.Distance.minPlaySliderHeight * 2)
        self.playSliderHeight = playSliderHeight
        // FIXME: here, `16` is duct tape. These icon calculations are all sorts of wrong
        fullIconHeight = barHeight - playSliderHeight - Constants.Distance.multiLineOSC_SpaceBetweenLines - 16
      } else {
        // Is single-line OSC
        self.playSliderHeight = barHeight
        // Reduce max button size so they don't touch edges or (if .top) icons above
        fullIconHeight = barHeight - (oscPosition == .top ? 8 : 4)
      }

      if forceSingleLineStyle || oscPosition == .top {
        // Single-line configuration: icon sizes & spacing are adjustable
        self.toolIconSize = ControlBarGeometry.iconSize(fromTicks: toolIconSizeTicks, fullHeight: fullIconHeight)
        self.toolIconSpacing = ControlBarGeometry.toolIconSpacing(fromTicks: toolIconSpacingTicks, fullHeight: fullIconHeight)
        self.playIconSize = ControlBarGeometry.iconSize(fromTicks: playIconSizeTicks, fullHeight: fullIconHeight)
        self.playIconSpacing = ControlBarGeometry.playIconSpacing(fromTicks: playIconSpacingTicks, fullHeight: fullIconHeight)

      } else {
        self.playIconSize = fullIconHeight
        self.toolIconSize = fullIconHeight
        self.toolIconSpacing = ControlBarGeometry.toolIconSpacing(fromTicks: 2, fullHeight: fullIconHeight)
        self.playIconSpacing = ControlBarGeometry.playIconSpacing(fromTicks: 2, fullHeight: fullIconHeight)
      }
    }

    self.barHeight = barHeight
    self.fullIconHeight = fullIconHeight

    self.position = oscPosition

    // Compute size of arrow buttons
    let arrowButtonAction = arrowButtonAction ?? Preference.enum(for: .arrowButtonAction)
    let arrowIconHeight: CGFloat
    switch arrowButtonAction {
    case .unused:
      arrowIconHeight = 0
    case .seek:
      arrowIconHeight = playIconSize * stepIconScaleFactor
    case .speed, .playlist:
      if #available(macOS 11.0, *) {
        // Using built-in MacOS symbols
        arrowIconHeight = playIconSize * systemArrowSymbolScaleFactor
      } else {
        // Legacy custom icons are scaled already:
        arrowIconHeight = playIconSize
      }
    }
    let leftArrowImage = ControlBarGeometry.leftArrowImage(given: arrowButtonAction)
    self.leftArrowImage = leftArrowImage
    self.rightArrowImage = ControlBarGeometry.rightArrowImage(given: arrowButtonAction)
    self.arrowIconWidth = leftArrowImage.deriveWidth(fromHeight: arrowIconHeight)
    self.arrowButtonAction = arrowButtonAction
    self.arrowIconHeight = arrowIconHeight
  }

  func clone(mode: PlayerWindowMode) -> ControlBarGeometry {
    return ControlBarGeometry(mode: mode, oscPosition: self.position,
                              toolbarItems: self.toolbarItems, arrowButtonAction: self.arrowButtonAction,
                              barHeight: self.barHeight,
                              toolIconSizeTicks: self.toolIconSizeTicks, toolIconSpacingTicks: self.toolIconSpacingTicks,
                              playIconSizeTicks: self.playIconSizeTicks, playIconSpacingTicks: self.playIconSpacingTicks)
  }

  var isValid: Bool {
    let playIconSizeTicks = playIconSizeTicks
    guard playIconSizeTicks.isBetweenInclusive(minTicks, and: maxTicks) else { return false }
    let playIconSpacingTicks = playIconSpacingTicks
    guard playIconSpacingTicks.isBetweenInclusive(minTicks, and: maxTicks) else { return false }
    let toolIconSizeTicks = toolIconSizeTicks
    guard toolIconSizeTicks.isBetweenInclusive(minTicks, and: maxTicks) else { return false }
    let toolIconSpacingTicks = toolIconSpacingTicks
    guard toolIconSpacingTicks.isBetweenInclusive(minTicks, and: maxTicks) else { return false }
    return true
  }

  var isMultiLineOSC: Bool { !forceSingleLineStyle && ControlBarGeometry.canUseMultiLineOSC(barHeight: barHeight, position) }

  var playSliderHeight: CGFloat

  var volumeIconHeight: CGFloat {
    if position == .floating {
      return floatingVolumeIconSize
    } else {
      return playIconSize
    }
  }

  var volumeSliderWidth: CGFloat {
    return 70
  }

  // MARK: Computed props: Playback Controls

  /// Font for each of `leftTimeLabel`, `rightTimeLabel`, to the left & right of the play slider, respectively.
  var timeLabelFont: NSFont {
    NSFont.monospacedDigitSystemFont(ofSize: timeLabelFontSize, weight: .medium)
  }

  var timeLabelFontSize: CGFloat {
    if mode == .musicMode {
      // Decrease font size of time labels for more compact display
      return 9
    }
    switch position {
    case .floating:
      return 10
    case .top, .bottom:
      return (playSliderHeight * 0.5).rounded().clamped(to: 13...24)
    }
  }

  var speedLabelFontSize: CGFloat {
    let idealSize = playIconSize * 0.25
    let freeHeight = fullIconHeight - playIconSize
    let deficit: CGFloat = max(0.0, idealSize - freeHeight)
    let compromise = idealSize - (0.5 * deficit)
    return compromise.clamped(to: 8...32)
  }

  /// Width of left, right, play btns + their spacing.
  /// Items will have `playIconSpacing` between each item, and `playIconSpacing * 0.5` for each of left margin & right margin.
  var totalPlayControlsWidth: CGFloat {
    let itemSizes = self.arrowButtonAction == .unused ? [playIconSize] : [arrowIconWidth, playIconSize, arrowIconWidth]
    let totalIconSpace = itemSizes.reduce(0, +)
    let totalInterIconSpace = playIconSpacing * CGFloat(itemSizes.count)
    return totalIconSpace + totalInterIconSpace
  }

  var leftArrowCenterXOffset: CGFloat {
    -rightArrowCenterXOffset
  }

  var rightArrowCenterXOffset: CGFloat {
     (playIconSize + arrowIconWidth) * 0.5 + playIconSpacing
  }
  
  var totalToolbarWidth: CGFloat {
    let totalIconSpacing: CGFloat = 2 * toolIconSpacing * CGFloat(toolbarItems.count + 1)
    let totalIconWidth = toolIconSize * CGFloat(toolbarItems.count)
    return totalIconWidth + totalIconSpacing
  }

  // MARK: Other functions

  func toolbarItemsAreSame(as otherGeo: ControlBarGeometry) -> Bool {
    let ours = toolbarItems.compactMap({ $0.rawValue })
    let theirs = otherGeo.toolbarItems.compactMap({ $0.rawValue })
    if ours.count != theirs.count {
      return false
    }
    for (o, t) in zip(ours, theirs) {
      if o != t {
        return false
      }
    }
    return true
  }

  // MARK: Static

  static func buttonSize(iconSize: CGFloat, iconSpacing: CGFloat) -> CGFloat {
    return iconSize + max(0, 2 * iconSpacing)
  }

  static var oscToolbarItems: [Preference.ToolBarButton] {
    get {
      return (Preference.array(for: .controlBarToolbarButtons) as? [Int] ?? []).compactMap(Preference.ToolBarButton.init(rawValue:))
    }
  }

  /// Prefs UI ticks → CGFloat
  private static func iconSize(fromTicks ticks: Int, fullHeight: CGFloat) -> CGFloat {
    let baseHeight = fullHeight * iconSizeBaseMultiplier
    let adjustableHeight = fullHeight - baseHeight

    let height = baseHeight + (adjustableHeight * (CGFloat(ticks) / CGFloat(maxTicks)))
    return height.rounded()
  }

  /// Prefs UI ticks → CGFloat
  private static func playIconSpacing(fromTicks ticks: Int, fullHeight: CGFloat) -> CGFloat {
    let baseHeight = fullHeight * playIconSpacingMinScaleMultiplier
    let adjustableHeight = fullHeight - baseHeight
    let adjustableHeight_Adjusted = adjustableHeight * CGFloat(ticks) / CGFloat(maxTicks) * playIconSpacingScaleMultiplier
    let spacing: CGFloat = (baseHeight + adjustableHeight_Adjusted).rounded()
    return spacing
  }

  /// Prefs UI ticks → CGFloat
  private static func toolIconSpacing(fromTicks ticks: Int, fullHeight: CGFloat) -> CGFloat {
    let spacing = fullHeight * CGFloat(ticks) / CGFloat(maxTicks) * toolSpacingScaleMultiplier
    return spacing.rounded()
  }

  static func leftArrowImage(given arrowButtonAction: Preference.ArrowButtonAction) -> NSImage {
    switch arrowButtonAction {
    case .playlist:
      return Images.prevTrack
    case .speed, .unused:
      return Images.rewind
    case .seek:
      return Images.stepBackward10
    }
  }

  static func rightArrowImage(given arrowButtonAction: Preference.ArrowButtonAction) -> NSImage {
    switch arrowButtonAction {
    case .playlist:
      return Images.nextTrack
    case .speed, .unused:
      return Images.fastForward
    case .seek:
      return Images.stepForward10
    }
  }

  static func canUseMultiLineOSC(barHeight: CGFloat, _ position: Preference.OSCPosition) -> Bool {
    guard position == .bottom else { return false }
    return barHeight >= Constants.Distance.multiLineOSC_minBarHeightThreshold
  }
}
