//
//  ControlBarGeometry.swift
//  iina
//
//  Created by Matt Svoboda on 9/8/24.
//  Copyright © 2024 lhc. All rights reserved.
//

import Foundation

fileprivate let iconSizeBaseMultiplier: CGFloat = 0.5
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

fileprivate let minMarginAbovePlayBtn: CGFloat = 16

// TODO: reimplement OSC title bar feature

struct ControlBarGeometry {
  static let minBarHeightForSpeedLabel: CGFloat = 30

  static var current = ControlBarGeometry()

  let position: Preference.OSCPosition

  let arrowBtnAction: Preference.ArrowButtonAction

  /// Preferred height for "full-width" OSCs (i.e. top/bottom, not floating/title bar)
  let barHeight: CGFloat
  
  let toolIconSize: CGFloat
  let toolIconSpacing: CGFloat

  /// Size of a side the 3 square playback button icons (Play/Pause, LeftArrow, RightArrow):
  let playIconSize: CGFloat

  /// This is usually the same as `playIconSize`, but can vary based on icon type
  let arrowIconSize: CGFloat

  /// Scale of spacing to the left & right of each playback button (for top/bottom OSC):
  let playIconSpacing: CGFloat

  let toolbarItems: [Preference.ToolBarButton]

  var volumeIconSize: CGFloat {
    if position == .floating {
      return floatingVolumeIconSize
    } else {
      return playIconSize
    }
  }

  var speedLabelFontSize: CGFloat {
    let idealSize = playIconSize * 0.25
    let freeHeight = barHeight - playIconSize
    let deficit: CGFloat = max(0.0, idealSize - freeHeight)
    let compromise = idealSize - (0.5 * deficit)
    return compromise.clamped(to: 8...32)
  }

  var playIconSizeWithSpeedLabel: CGFloat {
    guard barHeight >= ControlBarGeometry.minBarHeightForSpeedLabel else { return playIconSize }
    let freeHeight: CGFloat = barHeight - playIconSize
    let deficit: CGFloat = speedLabelFontSize - freeHeight + minMarginAbovePlayBtn
//    NSLog("IconSize:\(playIconSize), FreeHeight:\(freeHeight), Deficit:\(deficit)")
    return playIconSize - (deficit < 0.0 ? 0.0 : deficit)
  }

  /// All fields are optional. Any omitted fields will be filled in from preferences
  init(oscPosition: Preference.OSCPosition? = nil, toolbarItems: [Preference.ToolBarButton]? = nil,
       barHeight: CGFloat? = nil,
       toolIconSizeTicks: Int? = nil, toolIconSpacingTicks: Int? = nil,
       playIconSizeTicks: Int? = nil, playIconSpacingTicks: Int? = nil) {
    self.toolbarItems = toolbarItems ?? ControlBarGeometry.oscToolbarItems

    // First establish bar height
    let desiredBarHeight = barHeight ?? CGFloat(Preference.integer(for: .oscBarHeight))
    let barHeight = desiredBarHeight.clamped(to: Constants.Distance.minOSCBarHeight...Constants.Distance.maxOSCBarHeight)
    self.barHeight = barHeight

    let desiredToolIconSize = ControlBarGeometry.iconSize(fromTicks: toolIconSizeTicks,
                                                          barHeight: barHeight) ?? CGFloat(Preference.float(for: .oscBarToolbarIconSize))
    let desiredToolbarIconSpacing = ControlBarGeometry.toolIconSpacing(fromTicks: toolIconSpacingTicks,
                                                                   barHeight: barHeight) ?? CGFloat(Preference.float(for: .oscBarToolbarIconSpacing))
    let desiredPlayIconSize = ControlBarGeometry.iconSize(fromTicks: playIconSizeTicks,
                                                          barHeight: barHeight) ?? CGFloat(Preference.float(for: .oscBarPlaybackIconSize))
    let desiredPlayIconSpacing = ControlBarGeometry.playIconSpacing(fromTicks: playIconSpacingTicks,
                                                                barHeight: barHeight) ?? CGFloat(Preference.float(for: .oscBarPlaybackIconSpacing))

    let oscPosition = oscPosition ?? Preference.enum(for: .oscPosition)
    let playIconSize: CGFloat
    if oscPosition == .floating {
      self.toolIconSize = floatingToolbarIconSize
      self.toolIconSpacing = floatingToolbarIconSpacing
      playIconSize = floatingPlayIconSize
      self.playIconSpacing = floatingPlayIconSpacing
    } else {
      // Reduce max button size so they don't touch edges or (if .top) icons above
      let maxBtnHeight = barHeight - (oscPosition == .top ? 4 : 2)

      self.toolIconSize = desiredToolIconSize.clamped(to: minToolBtnHeight...maxBtnHeight)
      self.toolIconSpacing = max(0, desiredToolbarIconSpacing)
      playIconSize = desiredPlayIconSize.clamped(to: minPlayBtnHeight...maxBtnHeight)
      self.playIconSpacing = max(0, desiredPlayIconSpacing)
    }

    self.position = oscPosition
    self.playIconSize = playIconSize

    // Compute size of arrow buttons
    let arrowBtnAction: Preference.ArrowButtonAction = Preference.enum(for: .arrowButtonAction)
    self.arrowBtnAction = arrowBtnAction
    if arrowBtnAction == .seek {
      self.arrowIconSize = playIconSize * 0.75
    } else {
      self.arrowIconSize = playIconSize
    }
  }

  private static func iconSize(fromTicks ticks: Int?, barHeight: CGFloat) -> CGFloat? {
    guard let ticks else { return nil }

    let baseHeight = barHeight * iconSizeBaseMultiplier
    let adjustableHeight = barHeight - baseHeight

    return baseHeight + (adjustableHeight * (CGFloat(ticks) / maxTicks))
  }

  /// Width of left, right, play btns + their spacing
  var totalPlayControlsWidth: CGFloat {
    let itemSizes = [arrowIconSize, playIconSize, arrowIconSize]
    let totalIconSpace = itemSizes.reduce(0, +)
    let totalInterIconSpace = playIconSpacing * CGFloat(itemSizes.count + 1)
    return totalIconSpace + totalInterIconSpace
  }

  var leftArrowOffsetX: CGFloat {
    -rightArrowOffsetX
  }

  var rightArrowOffsetX: CGFloat {
    (playIconSize + arrowIconSize) * 0.5 + playIconSpacing
  }

  var playIconSizeTicks: Int {
    let baseHeight = barHeight * iconSizeBaseMultiplier
    let adjustableHeight = barHeight - baseHeight
    let ticks = (playIconSize - baseHeight) / adjustableHeight * maxTicks
    return Int(round(ticks))
  }

  var toolIconSizeTicks: Int {
    let baseHeight = barHeight * iconSizeBaseMultiplier
    let adjustableHeight = barHeight - baseHeight
    let ticks = (toolIconSize - baseHeight) / adjustableHeight * maxTicks
    return Int(round(ticks))
  }

  private static func toolIconSpacing(fromTicks ticks: Int?, barHeight: CGFloat) -> CGFloat? {
    guard let ticks else { return nil }

    return barHeight * CGFloat(ticks) / maxTicks / toolSpacingScaleMultiplier
  }

  var toolIconSpacingTicks: Int {
    return Int(round(toolIconSpacing * toolSpacingScaleMultiplier / barHeight * maxTicks))
  }

  private static func playIconSpacing(fromTicks ticks: Int?, barHeight: CGFloat) -> CGFloat? {
    guard let ticks else { return nil }

    return barHeight * ((CGFloat(ticks) / maxTicks) + playIconSpacingMinScaleMultiplier)
  }

  var playIconSpacingTicks: Int {
    let ticksDouble = ((playIconSpacing / barHeight) - playIconSpacingMinScaleMultiplier) * maxTicks
    return Int(round(ticksDouble))
  }

  static func buttonSize(iconSize: CGFloat, iconSpacing: CGFloat) -> CGFloat {
    return iconSize + max(0, 2 * iconSpacing)
  }

  static var oscToolbarItems: [Preference.ToolBarButton] {
    get {
      return (Preference.array(for: .controlBarToolbarButtons) as? [Int] ?? []).compactMap(Preference.ToolBarButton.init(rawValue:))
    }
  }

  var totalToolbarWidth: CGFloat {
    let totalIconSpacing: CGFloat = 2 * toolIconSpacing * CGFloat(toolbarItems.count + 1)
    let totalIconWidth = toolIconSize * CGFloat(toolbarItems.count)
    return totalIconWidth + totalIconSpacing
  }
}
