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

  var windowController: PlayerWindowController? {
    return window?.windowController as? PlayerWindowController
  }

  func updateSensitivity() {
    let sensitivityTick = Preference.integer(for: .volumeScrollAmount).clamped(to: 1...4)
    sensitivity = pow(10.0, Double(sensitivityTick) * 0.5 - 2.0)
    Logger.log.verbose("Updated VolumeSlider sensitivity to: \(sensitivity)")
  }

  /* TODO: decide about whether to auto-hide cursor when using scroll wheel
  override func scrollWheel(with event: NSEvent) {
    if let wc = windowController {
      let isTrackpadBegan = event.phase.contains(.began)
      if isTrackpadBegan {
        wc.hideCursor()
      }
    }

    super.scrollWheel(with: event)
  }*/
}
