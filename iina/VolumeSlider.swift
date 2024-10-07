//
//  VolumeSlider.swift
//  iina
//
//  Created by Matt Svoboda on 2024-10-06.
//  Copyright © 2024 lhc. All rights reserved.
//


final class VolumeSlider: ScrollableSlider {
  internal lazy var volumeScrollAmount: Int = Preference.integer(for: .volumeScrollAmount)

  /// See `updateSensitivity` below
  var _sensitivity: Double = 0.0
  override var sensitivity: Double { _sensitivity }

  required init?(coder: NSCoder) {
    super.init(coder: coder)
    updateSensitivity()
  }

  func updateSensitivity() {
    let sensitivityTick = Preference.integer(for: .volumeScrollAmount).clamped(to: 1...4)
    _sensitivity = pow(10.0, Double(sensitivityTick) * 0.5 - 2.0)
    Logger.log.verbose("Updated VolumeSlider sensitivity to: \(_sensitivity)")
  }

}
