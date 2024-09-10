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
fileprivate let floatingPlayBtnsSize: CGFloat = 24
fileprivate let floatingPlayBtnsHPad: CGFloat = 24

struct ControlBarGeometry {
  let barHeight: CGFloat
  let toolIconSize: CGFloat
  let toolIconSpacing: CGFloat
  let playIconSize: CGFloat
  let playIconSpacing: CGFloat

  init(barHeight: CGFloat? = nil,
       toolIconSizeTicks: Int? = nil, toolIconSpacingTicks: Int? = nil,
       playIconSizeTicks: Int? = nil, playIconSpacingTicks: Int? = nil) {
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

    let oscPosition: Preference.OSCPosition = Preference.enum(for: .oscPosition)
    if oscPosition == .floating {
      self.toolIconSize = floatingToolbarIconSize
      self.toolIconSpacing = floatingToolbarIconSpacing
      self.playIconSize = floatingPlayBtnsSize
      self.playIconSpacing = floatingPlayBtnsHPad
    } else {
      // Reduce max button size so they don't touch edges or (if .top) icons above
      let maxBtnHeight = barHeight - (oscPosition == .top ? 4 : 2)

      self.toolIconSize = desiredToolIconSize.clamped(to: minToolBtnHeight...maxBtnHeight)
      self.toolIconSpacing = max(0, desiredToolbarIconSpacing)
      self.playIconSize = desiredPlayIconSize.clamped(to: minPlayBtnHeight...maxBtnHeight)
      self.playIconSpacing = max(0, desiredPlayIconSpacing)
    }
  }

  private static func iconSize(fromTicks ticks: Int?, barHeight: CGFloat) -> CGFloat? {
    guard let ticks else { return nil }

    let baseHeight = barHeight * iconSizeBaseMultiplier
    let adjustableHeight = barHeight - baseHeight

    return baseHeight + (adjustableHeight * (CGFloat(ticks) / maxTicks))
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

}
