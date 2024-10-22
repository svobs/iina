//
//  VolumeSlider.swift
//  iina
//
//  Created by Matt Svoboda on 2024-10-06.
//  Copyright © 2024 lhc. All rights reserved.
//


final class VolumeSlider: ScrollableSlider {

  required init?(coder: NSCoder) {
    super.init(coder: coder)
    updateSensitivity()
  }

  func updateSensitivity() {
    let sensitivityTick = Preference.integer(for: .volumeScrollAmount).clamped(to: 1...4)
    sensitivity = pow(10.0, Double(sensitivityTick) * 0.5 - 2.0)
    stepScrollSensitivity = sensitivity
    Logger.log.verbose("Updated VolumeSlider sensitivity=\(sensitivity), stepScroll=\(stepScrollSensitivity)")
  }
}
