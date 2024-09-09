//
//  ControlBarGeometry.swift
//  iina
//
//  Created by Matt Svoboda on 9/8/24.
//  Copyright © 2024 lhc. All rights reserved.
//

import Foundation

fileprivate let iconSizeBaseMultiplier: CGFloat = 0.5
fileprivate let playIconSpacingBaseMultiplier: CGFloat = 0.1
fileprivate let tickCount: CGFloat = 4
fileprivate let ratioPerTick: CGFloat = 1 / tickCount
fileprivate let toolSpacingScaleMultiplier: CGFloat = 2.0

struct ControlBarGeometry {
  fileprivate static let minToolBtnHeight: CGFloat = 8
  fileprivate static let minPlayBtnHeight: CGFloat = 8
  fileprivate static let floatingToolbarIconSize: CGFloat = 14
  fileprivate static let floatingToolbarIconSpacing: CGFloat = 5
  fileprivate static let floatingPlayBtnsSize: CGFloat = 24
  fileprivate static let floatingPlayBtnsHPad: CGFloat = 24

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
      toolbarIconSize = ControlBarGeometry.floatingToolbarIconSize
      toolbarIconSpacing = ControlBarGeometry.floatingToolbarIconSpacing
      playIconSize = ControlBarGeometry.floatingPlayBtnsSize
      playIconSpacing = ControlBarGeometry.floatingPlayBtnsHPad
    case .top:
      // Play button is very tall. Reduce max size so it doesn't touch edges or icons above
      let maxPlayBtnHeight = barHeight - 4

      toolbarIconSize = desiredToolIconSize.clamped(to: ControlBarGeometry.minToolBtnHeight...barHeight)
      toolbarIconSpacing = max(0, desiredToolbarIconSpacing)
      playIconSize = desiredPlayIconSize.clamped(to: ControlBarGeometry.minPlayBtnHeight...maxPlayBtnHeight)
      playIconSpacing = max(0, desiredPlayIconSpacing)
    case .bottom:
      let maxPlayBtnHeight = barHeight - 2

      toolbarIconSize = desiredToolIconSize.clamped(to: ControlBarGeometry.minToolBtnHeight...barHeight)
      toolbarIconSpacing = max(0, desiredToolbarIconSpacing)
      playIconSize = desiredPlayIconSize.clamped(to: ControlBarGeometry.minPlayBtnHeight...maxPlayBtnHeight)
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

  private static func toolIconSpacing(fromTicks ticks: Int?, barHeight: CGFloat) -> CGFloat? {
    guard let ticks else { return nil }

    return barHeight * CGFloat(ticks) * ratioPerTick / toolSpacingScaleMultiplier
  }

  private static func playIconSpacing(fromTicks ticks: Int?, barHeight: CGFloat) -> CGFloat? {
    guard let ticks else { return nil }

    return barHeight * ((CGFloat(ticks) * ratioPerTick) + playIconSpacingBaseMultiplier)
  }

  var playIconSpacingTicks: Int {
    let ticksDouble = ((playIconSpacing / barHeight) - playIconSpacingBaseMultiplier) * tickCount
    return Int(round(ticksDouble))
  }

  var toolIconSizeTicks: Int {
    let baseHeight = barHeight * iconSizeBaseMultiplier
    return Int(round((toolIconSize - baseHeight) * ratioPerTick))
  }

  var toolIconSpacingTicks: Int {
    return Int(round(toolIconSpacing * toolSpacingScaleMultiplier / barHeight * tickCount))
  }

  var playIconSizeTicks: Int {
    let baseHeight = barHeight * iconSizeBaseMultiplier
    return Int(round((playIconSize - baseHeight) * ratioPerTick))
  }
}
