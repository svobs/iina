//
//  OSCSymButton.swift
//  iina
//
//  Created by Matt Svoboda on 2025-02-03.
//  Copyright © 2025 lhc. All rights reserved.
//

/// A `SymButton` which is in an OSC.
class OSCSymButton: SymButton {
  override func configureSelf() {
    super.configureSelf()
    useDefaultColors()
  }
  /// Sets current tint as a side effect! Do not use if currently between mouseDown & mouseUp.
  private func useDefaultColors() {
    regularColor = nil
    highlightColor = .controlTextColor
    setShadowForOSC(enabled: false)
    updateHighlight(isInsideBounds: false)
  }

  /// Sets current tint as a side effect! Do not use if currently between mouseDown & mouseUp.
  private func useColorsForClearBG() {
    regularColor = .controlForClearBG
    highlightColor = .white
    setShadowForOSC(enabled: true)
    updateHighlight(isInsideBounds: false)
  }

  /// Sets current tint as a side effect! Do not use if currently between mouseDown & mouseUp.
  func setOSCColors(hasClearBG: Bool) {
    if hasClearBG {
      useColorsForClearBG()
    } else {
      useDefaultColors()
    }
  }

  func setShadowForOSC(enabled: Bool) {
    if enabled {
      guard shadow == nil else { return }
      // Shadow for clear BG
      addShadow(blurRadiusConstant: 0.5, xOffsetConstant: 0, yOffsetConstant: 0, color: .black)
    } else {
      shadow = nil
    }
  }

}
