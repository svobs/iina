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
fileprivate let tickCount: CGFloat = 4
fileprivate let ratioPerTick: CGFloat = 1 / tickCount
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
    let barHeight = max(Constants.Distance.minOSCBarHeight, desiredBarHeight)

    let desiredToolIconSize = ControlBarGeometry.iconSize(fromTicks: toolIconSizeTicks,
                                                          barHeight: barHeight) ?? CGFloat(Preference.float(for: .oscBarToolbarIconSize))
    let desiredToolbarIconSpacing = ControlBarGeometry.toolIconSpacing(fromTicks: toolIconSpacingTicks,
                                                                   barHeight: barHeight) ?? CGFloat(Preference.float(for: .oscBarToolbarIconSpacing))
    let desiredPlayIconSize = ControlBarGeometry.iconSize(fromTicks: playIconSizeTicks,
                                                          barHeight: barHeight) ?? CGFloat(Preference.float(for: .oscBarPlaybackIconSize))
    let desiredPlayIconSpacing = ControlBarGeometry.playIconSpacing(fromTicks: playIconSpacingTicks,
                                                                barHeight: barHeight) ?? CGFloat(Preference.float(for: .oscBarPlaybackIconSpacing))

    let toolbarIconSize: CGFloat
    let toolbarIconSpacing: CGFloat
    let playIconSize: CGFloat
    let playIconSpacing: CGFloat

    let oscPosition: Preference.OSCPosition = Preference.enum(for: .oscPosition)
    switch oscPosition {
    case .floating:
      toolbarIconSize = floatingToolbarIconSize
      toolbarIconSpacing = floatingToolbarIconSpacing
      playIconSize = floatingPlayBtnsSize
      playIconSpacing = floatingPlayBtnsHPad
    case .top:
      // Play button is very tall. Reduce max size so it doesn't touch edges or icons above
      let maxPlayBtnHeight = barHeight - 4

      toolbarIconSize = desiredToolIconSize.clamped(to: minToolBtnHeight...barHeight)
      toolbarIconSpacing = max(0, desiredToolbarIconSpacing)
      playIconSize = desiredPlayIconSize.clamped(to: minPlayBtnHeight...maxPlayBtnHeight)
      playIconSpacing = max(0, desiredPlayIconSpacing)
    case .bottom:
      let maxPlayBtnHeight = barHeight - 2

      toolbarIconSize = desiredToolIconSize.clamped(to: minToolBtnHeight...barHeight)
      toolbarIconSpacing = max(0, desiredToolbarIconSpacing)
      playIconSize = desiredPlayIconSize.clamped(to: minPlayBtnHeight...maxPlayBtnHeight)
      playIconSpacing = max(0, desiredPlayIconSpacing)
    }

    self.barHeight = barHeight
    self.toolIconSize = toolbarIconSize
    self.toolIconSpacing = toolbarIconSpacing
    self.playIconSize = playIconSize
    self.playIconSpacing = playIconSpacing
  }

  private static func iconSize(fromTicks ticks: Int?, barHeight: CGFloat) -> CGFloat? {
    guard let ticks else { return nil }

    let baseHeight = barHeight * iconSizeBaseMultiplier
    let adjustableHeight = barHeight - baseHeight

    return baseHeight + (adjustableHeight * (CGFloat(ticks) * ratioPerTick))
  }

  var playIconSizeTicks: Int {
    let baseHeight = barHeight * iconSizeBaseMultiplier
    let adjustableHeight = barHeight - baseHeight
    let ticks = (playIconSize - baseHeight) / adjustableHeight * tickCount
    return Int(round(ticks))
  }

  var toolIconSizeTicks: Int {
    let baseHeight = barHeight * iconSizeBaseMultiplier
    let adjustableHeight = barHeight - baseHeight
    let ticks = (toolIconSize - baseHeight) / adjustableHeight * tickCount
    return Int(round(ticks))
  }

  private static func toolIconSpacing(fromTicks ticks: Int?, barHeight: CGFloat) -> CGFloat? {
    guard let ticks else { return nil }

    return barHeight * CGFloat(ticks) * ratioPerTick / toolSpacingScaleMultiplier
  }

  var toolIconSpacingTicks: Int {
    return Int(round(toolIconSpacing * toolSpacingScaleMultiplier / barHeight * tickCount))
  }

  private static func playIconSpacing(fromTicks ticks: Int?, barHeight: CGFloat) -> CGFloat? {
    guard let ticks else { return nil }

    return barHeight * ((CGFloat(ticks) * ratioPerTick) + playIconSpacingMinScaleMultiplier)
  }

  var playIconSpacingTicks: Int {
    let ticksDouble = ((playIconSpacing / barHeight) - playIconSpacingMinScaleMultiplier) * tickCount
    return Int(round(ticksDouble))
  }

}
