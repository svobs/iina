//
//  ControlBarGeometry.swift
//  iina
//
//  Created by Matt Svoboda on 9/8/24.
//  Copyright © 2024 lhc. All rights reserved.
//

import Foundation

fileprivate let iconSizeBaseMultiplier: CGFloat = 0.5
fileprivate let playIconSpacingScaleMultiplier: CGFloat = 2.0
fileprivate let playIconSpacingMinScaleMultiplier: CGFloat = 0.1
fileprivate let maxTicks: CGFloat = 4
fileprivate let toolSpacingScaleMultiplier: CGFloat = 2.0

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
fileprivate let systemArrowSymbolScaleFactor: CGFloat = 0.65

// TODO: reimplement OSC title bar feature

struct ControlBarGeometry {
  // MARK: Stored properties

  let mode: PlayerWindowMode
  let position: Preference.OSCPosition

  let arrowButtonAction: Preference.ArrowButtonAction

  /// Preferred height for "full-width" OSCs (i.e. top/bottom, not floating/title bar)
  let barHeight: CGFloat

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
       toolIconSizeTicks: Int? = nil, toolIconSpacingTicks: Int? = nil,
       playIconSizeTicks: Int? = nil, playIconSpacingTicks: Int? = nil) {
    self.mode = mode
    self.toolbarItems = toolbarItems ?? ControlBarGeometry.oscToolbarItems

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
    let playIconSize: CGFloat
    if mode == .musicMode {
      barHeight = musicModeBarHeight
      playIconSize = musicModePlayIconSize
      self.toolIconSize = musicModeToolbarIconSize
      self.toolIconSpacing = musicModeToolbarIconSpacing
      self.playIconSpacing = musicModePlayIconSpacing

    } else if oscPosition == .floating {
      barHeight = 67  // not really useful here anyway
      self.toolIconSize = floatingToolbarIconSize
      self.toolIconSpacing = floatingToolbarIconSpacing
      playIconSize = floatingPlayIconSize
      self.playIconSpacing = floatingPlayIconSpacing

    } else {
      // First establish bar height
      let desiredBarHeight = desiredBarHeight ?? CGFloat(Preference.integer(for: .oscBarHeight))
      barHeight = desiredBarHeight.clamped(to: Constants.Distance.minOSCBarHeight...Constants.Distance.maxOSCBarHeight)

      let desiredToolIconSize = ControlBarGeometry.iconSize(fromTicks: toolIconSizeTicks,
                                                            barHeight: barHeight) ?? CGFloat(Preference.float(for: .oscBarToolIconSize))
      let desiredToolbarIconSpacing = ControlBarGeometry.toolIconSpacing(fromTicks: toolIconSpacingTicks,
                                                                         barHeight: barHeight) ?? CGFloat(Preference.float(for: .oscBarToolIconSpacing))
      let desiredPlayIconSize = ControlBarGeometry.iconSize(fromTicks: playIconSizeTicks,
                                                            barHeight: barHeight) ?? CGFloat(Preference.float(for: .oscBarPlayIconSize))
      let desiredPlayIconSpacing = ControlBarGeometry.playIconSpacing(fromTicks: playIconSpacingTicks,
                                                                      barHeight: barHeight) ?? CGFloat(Preference.float(for: .oscBarPlayIconSpacing))

      // Reduce max button size so they don't touch edges or (if .top) icons above
      let maxBtnHeight = barHeight - (oscPosition == .top ? 4 : 2)

      self.toolIconSize = desiredToolIconSize.clamped(to: minToolBtnHeight...maxBtnHeight)
      self.toolIconSpacing = max(0, desiredToolbarIconSpacing)
      self.playIconSpacing = max(0, desiredPlayIconSpacing)
      playIconSize = desiredPlayIconSize.clamped(to: minPlayBtnHeight...maxBtnHeight)
    }

    self.barHeight = barHeight
    self.playIconSize = playIconSize
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
    let maxTicks = Int(maxTicks)
    let playIconSizeTicks = playIconSizeTicks
    guard playIconSizeTicks.isBetweenInclusive(0, and: maxTicks) else { return false }
    let playIconSpacingTicks = playIconSpacingTicks
    guard playIconSpacingTicks.isBetweenInclusive(0, and: maxTicks) else { return false }
    let toolIconSizeTicks = toolIconSizeTicks
    guard toolIconSizeTicks.isBetweenInclusive(0, and: maxTicks) else { return false }
    let toolIconSpacingTicks = toolIconSpacingTicks
    guard toolIconSpacingTicks.isBetweenInclusive(0, and: maxTicks) else { return false }
    return true
  }

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

  var speedLabelFontSize: CGFloat {
    let idealSize = playIconSize * 0.25
    let freeHeight = barHeight - playIconSize
    let deficit: CGFloat = max(0.0, idealSize - freeHeight)
    let compromise = idealSize - (0.5 * deficit)
    return compromise.clamped(to: 8...32)
  }

  /// Width of left, right, play btns + their spacing
  var totalPlayControlsWidth: CGFloat {
    let itemSizes = self.arrowButtonAction == .unused ? [playIconSize] : [arrowIconWidth, playIconSize, arrowIconWidth]
    let totalIconSpace = itemSizes.reduce(0, +)
    if itemSizes.count <= 1 {
      return totalIconSpace + playIconSpacing
    }
    let totalInterIconSpace = playIconSpacing * CGFloat(itemSizes.count + 1)
    return totalIconSpace + totalInterIconSpace
  }

  var leftArrowOffsetX: CGFloat {
    -rightArrowOffsetX
  }

  var rightArrowOffsetX: CGFloat {
    (playIconSize + arrowIconWidth) * 0.5 + playIconSpacing
  }
  
  var totalToolbarWidth: CGFloat {
    let totalIconSpacing: CGFloat = 2 * toolIconSpacing * CGFloat(toolbarItems.count + 1)
    let totalIconWidth = toolIconSize * CGFloat(toolbarItems.count)
    return totalIconWidth + totalIconSpacing
  }

  var arrowButtonSymConfig: NSImage.SymbolConfiguration {
    let weight: NSFont.Weight
    if arrowButtonAction == .seek {
      weight = .medium
    } else {
      weight = .ultraLight
    }
    return NSImage.SymbolConfiguration(pointSize: 12, weight: weight, scale: .small)
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
  private static func iconSize(fromTicks ticks: Int?, barHeight: CGFloat) -> CGFloat? {
    guard let ticks else { return nil }

    let baseHeight = barHeight * iconSizeBaseMultiplier
    let adjustableHeight = barHeight - baseHeight

    let height = baseHeight + (adjustableHeight * (CGFloat(ticks) / maxTicks))
    return height.rounded()
  }

  /// Prefs UI ticks → CGFloat
  private static func playIconSpacing(fromTicks ticks: Int?, barHeight: CGFloat) -> CGFloat? {
    guard let ticks else { return nil }

    let spacing = barHeight * (((CGFloat(ticks) / maxTicks) / playIconSpacingScaleMultiplier) + playIconSpacingMinScaleMultiplier)
    return spacing.rounded()
  }

  /// Prefs UI ticks → CGFloat
  private static func toolIconSpacing(fromTicks ticks: Int?, barHeight: CGFloat) -> CGFloat? {
    guard let ticks else { return nil }

    let spacing = barHeight * CGFloat(ticks) / maxTicks / toolSpacingScaleMultiplier
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
}
