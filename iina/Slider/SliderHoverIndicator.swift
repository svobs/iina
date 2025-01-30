//
//  PlaySliderLoopKnob.swift
//  iina
//
//  Created by low-batt on 10/14/21.
//  Copyright © 2021 lhc. All rights reserved.
//

import Cocoa

final class SliderHoverIndicator: NSImageView {
  private let slider: PlaySlider
  private var centerXConstraint: NSLayoutConstraint!

  /// Size in points
  init(slider: PlaySlider, size: NSSize, scaleFactor: CGFloat) {
    self.slider = slider
    // The frame is calculated and set once the superclass is initialized.
    super.init(frame: .zero)
    layerContentsRedrawPolicy = .never
    // This knob is hidden unless the mouse is hovering inside the slider.
    isHidden = true
    slider.addSubview(self)
    //    image = NSImage(cgImage: indicatorImage, size: size * scaleFactor)
    setFrameSize(size)
    imageAlignment = .alignCenter
    imageScaling = .scaleNone

    translatesAutoresizingMaskIntoConstraints = false
    centerYAnchor.constraint(equalTo: slider.centerYAnchor).isActive = true

    centerXConstraint = centerXAnchor.constraint(equalTo: slider.leadingAnchor,
                                                 constant: size.width * 0.5)
    centerXConstraint.isActive = true
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}
