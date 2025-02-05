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
  var imgLayer: IndicatorImgLayer

  /// Size in points
  init(slider: PlaySlider, scaleFactor: CGFloat) {
    let size = slider.indicatorSize()
    self.slider = slider
    imgLayer = IndicatorImgLayer(size, scaleFactor: scaleFactor)
    // The frame is calculated and set once the superclass is initialized.
    super.init(frame: .zero)
    slider.addSubview(self)
    setFrameSize(size)
    isHidden = true
    idString = slider.idString + "\(slider.idString)HoverIndicator"

    layer = imgLayer
    wantsLayer = true
    layerContentsRedrawPolicy = .onSetNeedsDisplay
    layerContentsPlacement = .center

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

  func update(scaleFactor: CGFloat) {
    let size = slider.indicatorSize()
    setFrameSize(size)
    widthConstraint.animateToConstant(size.width)
    heightConstraint.animateToConstant(size.height)

    imgLayer = IndicatorImgLayer(size, scaleFactor: scaleFactor)
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
    init(_ size: CGSize, scaleFactor: CGFloat) {
      super.init()
      contentsScale = scaleFactor
      bounds = CGRect(origin: .zero, size: size * scaleFactor)
    }

    override init(layer: Any) {
      let prevLayer = layer as! IndicatorImgLayer
      super.init()
      contentsScale = prevLayer.contentsScale
      bounds = prevLayer.bounds
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func draw(in ctx: CGContext) {
      Logger.log("*** DRAW LAYER *** \(bounds.size) scale=\(contentsScale)")  // TODO: remove
      
      // TODO!

      // Use entire img height for now. In the future, would be better to make taller than the main knob.
      // Need to investigate drawing directly to CGLayers
      let indicatorRect = NSRect(origin: .zero, size: bounds.size)
      let cornerRadius: CGFloat = 1.0 //(bounds.size.height * 0.25).rounded()
      ctx.addPath(CGPath(roundedRect: indicatorRect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil))
      ctx.setFillColor(NSColor.sliderHoverIndicator.cgColor)
      ctx.fillPath()
    }
  }
}
