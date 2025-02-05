//
//  PlaySlider.swift
//  iina
//
//  Created by low-batt on 10/11/21.
//  Copyright © 2021 lhc. All rights reserved.
//

import Cocoa

/// A custom [slider](https://developer.apple.com/design/human-interface-guidelines/macos/selectors/sliders/)
/// for the onscreen controller.
///
/// This slider adds two thumbs (referred to as knobs in code) to the progress bar slider to show the A and B loop points of the
/// [mpv](https://mpv.io/manual/stable/) A-B loop feature and allow the loop points to be adjusted. When the feature is
/// disabled the additional thumbs are hidden.
/// - Requires: The custom slider cell provided by `PlaySliderCell` **must** be used with this class.
/// - Note: Unlike `NSSlider` the `draw` method of this class will do nothing if the view is hidden.
final class PlaySlider: ScrollableSlider {
  /// Cache this to keep track of PlaySliderLoopKnob style
  var isDarkMode: Bool = false

  /// Knob representing the A loop point for the mpv A-B loop feature.
  var abLoopA: PlaySliderLoopKnob { abLoopAKnob }

  /// Knob representing the B loop point for the mpv A-B loop feature.
  var abLoopB: PlaySliderLoopKnob { abLoopBKnob }

  /// The slider's cell correctly typed for convenience.
  var customCell: PlaySliderCell { cell as! PlaySliderCell }

  var hoverIndicator: SliderHoverIndicator?

  // MARK:- Private Properties

  private var abLoopAKnob: PlaySliderLoopKnob!

  private var abLoopBKnob: PlaySliderLoopKnob!

  private var player: PlayerCore {
    return customCell.player
  }

  // MARK:- Initialization

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    cell = PlaySliderCell()
    abLoopAKnob = PlaySliderLoopKnob(slider: self, toolTip: "A-B loop A")
    abLoopBKnob = PlaySliderLoopKnob(slider: self, toolTip: "A-B loop B")
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  // MARK:- Drawing

  /// Draw the slider.
  ///
  /// The [NSSlider](https://developer.apple.com/documentation/appkit/nsslider) method is being overridden
  /// for two reasons.
  ///
  /// With the onscreen controller hidden and a movie playing spindumps showed time being spent drawing the slider even though it
  /// was not visible. Apparently `NSSlider.draw` is not calling
  /// [hiddenOrHasHiddenAncestor](https://developer.apple.com/documentation/appkit/nsview/1483473-hiddenorhashiddenancestor)
  /// to see if drawing can be avoided.  This was noticed under macOS Monterey.  Unknown if Apple addressed this in later macOS
  /// releases.
  ///
  /// The loop knobs are added as subviews to the slider. That should have resulted in the `PlaySliderLoopKnob.draw` method
  /// being called when the slider was being drawn. Prior to macOS Sonoma that did not occur. The assumption is that the
  /// [NSSlider](https://developer.apple.com/documentation/appkit/nsslider) `draw` method was not calling
  /// `super.draw` and that has now been corrected. As a workaround on earlier versions of macOS the loop knob `draw` method
  /// is called directly.
  override func draw(_ dirtyRect: NSRect) {
    let sliderAppearance = customCell.sliderAppearance!
    super.draw(dirtyRect)
    let isDark = sliderAppearance.isDark
    if isDark != isDarkMode {
      sliderAppearance.applyAppearanceFor {
        isDarkMode = isDark
        abLoopA.updateKnobImage(to: .loopKnob)
        abLoopB.updateKnobImage(to: .loopKnob)
      }
    }
    abLoopA.updateHorizontalPosition()
    abLoopB.updateHorizontalPosition()
  }

  override func viewDidUnhide() {
    super.viewDidUnhide()
    // When IINA is not the application being used and the onscreen controller is hidden if the
    // mouse is moved over an IINA window the IINA will unhide the controller. If the slider is
    // not marked as needing display the controller will show without the slider. I would have
    // thought the NSView method would do this. The current Apple documentation does not say what
    // the NSView method does or even if it needs to be called by subclasses.
    needsDisplay = true
  }

  override func mouseUp(with event: NSEvent) {
    player.windowController.mouseUp(with: event)
  }

  func showHoverIndicator(atSliderCoordX x: CGFloat) {
    guard let scaleFactor = window?.screen?.backingScaleFactor,
          let sliderAppearance = customCell.sliderAppearance else { return }

    let xInWindowCoord = self.convert(NSPoint(x: x, y: 0), to: nil).x

    // Do not draw over the main knob, or AB loop knobs
    if customCell.wantsKnob {
      let knobRect = customCell.knobRect(flipped: isFlipped)
      if xInWindowCoord.isBetweenInclusive(knobRect.minX, and: knobRect.maxX) {
        hoverIndicator?.isHidden = true
        return
      }
    }
    if !abLoopA.isHidden {
      let knobCenterX = abLoopA.x
      let kf = KnobFactory.shared
      let halfWidth = kf.loopKnobWidth(mainKnobWidth: customCell.knobWidth) * 0.5
      if xInWindowCoord.isBetweenInclusive(knobCenterX - halfWidth, and: knobCenterX - halfWidth) {
        hoverIndicator?.isHidden = true
        return
      }
    }
    if !abLoopB.isHidden {
      let knobCenterX = abLoopB.x
      let kf = KnobFactory.shared
      let halfWidth = kf.loopKnobWidth(mainKnobWidth: customCell.knobWidth) * 0.5
      if xInWindowCoord.isBetweenInclusive(knobCenterX - halfWidth, and: knobCenterX - halfWidth) {
        hoverIndicator?.isHidden = true
        return
      }
    }

    sliderAppearance.applyAppearanceFor {
      let indicator: SliderHoverIndicator
      if let hoverIndicator, hoverIndicator.imgLayer.contentsScale == scaleFactor {
        indicator = hoverIndicator
      } else {
        if let prevIndicator = hoverIndicator {
          prevIndicator.dispose()
        }
        let indicatorSize = NSSize(width: max(2.0, (customCell.knobWidth * 0.25).rounded()), height: customCell.knobHeight)
        indicator = SliderHoverIndicator(slider: self, size: indicatorSize, scaleFactor: scaleFactor)
        hoverIndicator = indicator
      }

      indicator.show(atSliderCoordX: x)
    }
  }
}
