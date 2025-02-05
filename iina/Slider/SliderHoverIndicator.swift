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
  private var centerXConstraint: NSLayoutConstraint!

  let imgLayer: IndicatorImgLayer

  /// Size in points
  init(slider: PlaySlider, size: NSSize, scaleFactor: CGFloat) {
    self.slider = slider
    imgLayer = IndicatorImgLayer(size, scaleFactor: scaleFactor)
    // The frame is calculated and set once the superclass is initialized.
    super.init(frame: .zero)
    slider.addSubview(self)
    setFrameSize(size)
    isHidden = true

    layer = imgLayer
    wantsLayer = true
    layerContentsRedrawPolicy = .onSetNeedsDisplay
    layerContentsPlacement = .center

    translatesAutoresizingMaskIntoConstraints = false
    heightAnchor.constraint(equalToConstant: size.height).isActive = true
    widthAnchor.constraint(equalToConstant: size.width).isActive = true
    centerYAnchor.constraint(equalTo: slider.centerYAnchor).isActive = true

    centerXConstraint = centerXAnchor.constraint(equalTo: slider.leadingAnchor,
                                                 constant: size.width * 0.5)
    centerXConstraint.isActive = true
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  override func draw(_ dirtyRect: NSRect) {
    Logger.log("*** DRAW *** dirtyRect: \(dirtyRect)")  // TODO: remove
    let ctx = NSGraphicsContext.current!.cgContext
    imgLayer.draw(in: ctx)
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
      contentsFormat = prevLayer.contentsFormat
    }

    required init?(coder: NSCoder) {
      fatalError("init(coder:) has not been implemented")
    }

    override func draw(in ctx: CGContext) {
      Logger.log("*** DRAW LAYER *** \(bounds.size) scale=\(contentsScale)")  // TODO: remove
      
      // TODO!

      // Use entire img height for now. In the future, would be better to make taller than the main knob.
      // Need to investigate drawing directly to CGLayers
      let indicatorRect = NSRect(x: 0, y: 0, width: bounds.width - 2, height: bounds.height - 2)
      ctx.addPath(CGPath(rect: indicatorRect, transform: nil))
      ctx.setFillColor(.white)
      ctx.fillPath()
    }
  }
}
