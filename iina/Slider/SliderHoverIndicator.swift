//
//  PlaySliderLoopKnob.swift
//  iina
//
//  Created by low-batt on 10/14/21.
//  Copyright © 2021 lhc. All rights reserved.
//

import Cocoa

final class SliderHoverIndicator: NSView {
  private let slider: PlaySlider
  private var heightConstraint: NSLayoutConstraint!
  private var widthConstraint: NSLayoutConstraint!
  private var centerXConstraint: NSLayoutConstraint!
//  var imgLayer: IndicatorImgLayer { layer as! IndicatorImgLayer }
  var imgLayer: IndicatorImgLayer

  /// Size in points
  init(slider: PlaySlider, oscGeo: ControlBarGeometry, scaleFactor: CGFloat, isDark: Bool) {
    let size = oscGeo.sliderIndicatorSize
    self.slider = slider
    imgLayer = IndicatorImgLayer(size, scaleFactor: scaleFactor, isDark: isDark)
    // The frame is calculated and set once the superclass is initialized.
    super.init(frame: NSRect(origin: .zero, size: size))
    slider.addSubview(self)
    isHidden = true
    idString = slider.idString + "\(slider.idString)HoverIndicator"

    layer = imgLayer
    wantsLayer = true
    layerContentsRedrawPolicy = .onSetNeedsDisplay
    layerContentsPlacement = .center
    setFrameSize(size)

    translatesAutoresizingMaskIntoConstraints = false

    widthConstraint = widthAnchor.constraint(equalToConstant: size.width)
    widthConstraint.identifier = "\(idString)-WidthConstraint"
    widthConstraint.isActive = true

    heightConstraint = heightAnchor.constraint(equalToConstant: size.height)
    heightConstraint.identifier = "\(idString)-HeightConstraint"
    heightConstraint.isActive = true

    // Do not change:
    let centerYConstraint = centerYAnchor.constraint(equalTo: slider.centerYAnchor)
    centerYConstraint.identifier = "\(idString)-CenterYConstraint"
    centerYConstraint.isActive = true

    centerXConstraint = centerXAnchor.constraint(equalTo: slider.leadingAnchor,
                                                 constant: size.width * 0.5)
    centerXConstraint.identifier = "\(idString)-CenterXConstraint"
    centerXConstraint.isActive = true
  }

  func dispose() {
    centerXConstraint.isActive = false
    layer =  nil
    removeFromSuperview()
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  func update(scaleFactor: CGFloat, oscGeo: ControlBarGeometry, isDark: Bool) {
    slider.associatedPlayer?.log.verbose("Updating SliderHoverIndicator: isDark=\(isDark.yn)")
    let size = oscGeo.sliderIndicatorSize
    imgLayer = IndicatorImgLayer(size, scaleFactor: scaleFactor, isDark: isDark)
    layer = imgLayer
    setFrameSize(size)
    widthConstraint.animateToConstant(size.width)
    heightConstraint.animateToConstant(size.height)
    needsDisplay = true
  }

  func show(atSliderCoordX sliderCoordX: CGFloat) {
    centerXConstraint.constant = sliderCoordX
    if isHidden || alphaValue != 1.0 {
      needsDisplay = true
    }
    isHidden = false
    alphaValue = 1.0
  }

  class IndicatorImgLayer: CALayer {
    let isDark: Bool
    init(_ size: CGSize, scaleFactor: CGFloat, isDark: Bool) {
      self.isDark = isDark
      super.init()
      contentsScale = scaleFactor
      bounds = CGRect(origin: .zero, size: size * scaleFactor)
    }

    override init(layer: Any) {
      let prevLayer = layer as! IndicatorImgLayer
      isDark = prevLayer.isDark
      super.init()
      contentsScale = prevLayer.contentsScale
      bounds = prevLayer.bounds
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func draw(in ctx: CGContext) {
      let indicatorRect = NSRect(origin: .zero, size: bounds.size)
      let cornerRadius: CGFloat = 1.0
      ctx.clear(indicatorRect)
      ctx.addPath(CGPath(roundedRect: indicatorRect,
                         cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil))
      let color: NSColor = isDark ? .sliderHoverIndicatorDark : .sliderHoverIndicatorLight
      ctx.setFillColor(color.cgColor)
      ctx.fillPath()
    }
  }
}
