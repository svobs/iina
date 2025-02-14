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
  var imgLayer: IndicatorImgLayer { layer as! IndicatorImgLayer }

  /// Size in points
  init(slider: PlaySlider, oscGeo: ControlBarGeometry, scaleFactor: CGFloat, isDark: Bool) {
    let size = oscGeo.sliderIndicatorSize
    self.slider = slider
    // The frame is calculated and set once the superclass is initialized.
    super.init(frame: NSRect(origin: .zero, size: size))
    slider.addSubview(self)
    layer = IndicatorImgLayer(size, scaleFactor: scaleFactor, isDark: isDark)
    isHidden = true
    idString = slider.idString + "\(slider.idString)HoverIndicator"

    wantsLayer = true
    layerContentsRedrawPolicy = .onSetNeedsDisplay

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
    slider.associatedPlayer?.log.verbose{"Updating SliderHoverIndicator: isDark=\(isDark.yn)"}
    let size = oscGeo.sliderIndicatorSize
    widthConstraint.animateToConstant(size.width)
    heightConstraint.animateToConstant(size.height)
    // For some reason, the drawing disappears if the layer is replaced. Must reuse existing layer.
    imgLayer.updateState(size, scaleFactor: scaleFactor, isDark: isDark)
    needsDisplay = true
  }

  func show(atSliderCoordX sliderCoordX: CGFloat) {
//    slider.associatedPlayer?.log.verbose{"Showing SliderHoverIndicator @x=\(sliderCoordX)"}
    centerXConstraint.constant = sliderCoordX
    if isHidden || alphaValue != 1.0 {
      needsDisplay = true
    }
    isHidden = false
    alphaValue = 1.0
  }

  class IndicatorImgLayer: CALayer {
    var isDark: Bool = false

    init(_ size: CGSize, scaleFactor: CGFloat, isDark: Bool) {
      super.init()
      updateState(size, scaleFactor: scaleFactor, isDark: isDark)
    }

    override init(layer: Any) {
      let prevLayer = layer as! IndicatorImgLayer
      super.init()
      isDark = prevLayer.isDark
      contentsScale = prevLayer.contentsScale
      bounds = prevLayer.bounds
    }

    func updateState(_ size: CGSize, scaleFactor: CGFloat, isDark: Bool) {
      self.isDark = isDark
      contentsScale = scaleFactor
      bounds = CGRect(origin: .zero, size: size * scaleFactor)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func draw(in ctx: CGContext) {
      let indicatorRect = bounds
      let cornerRadius: CGFloat = 1.0
      ctx.addPath(CGPath(roundedRect: indicatorRect,
                         cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil))
      let color: NSColor = isDark ? .sliderHoverIndicatorDark : .sliderHoverIndicatorLight
      ctx.setFillColor(color.cgColor)
      ctx.fillPath()
    }
  }
}
