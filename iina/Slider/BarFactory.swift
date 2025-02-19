//
//  BarFactory.swift
//  iina
//
//  Created by Matt Svoboda on 2024-11-07.
//

/// In points, not pixels
fileprivate let barImgPadding: CGFloat = 1.0
fileprivate let barVerticalPaddingTotal = barImgPadding * 2

fileprivate extension CGColor {
  func exaggerated() -> CGColor {
    var colorsComps: [CGFloat] = []
    let numComponents = min(self.numberOfComponents, 3)
    for i in 0..<numComponents {
      colorsComps.append((self.components![i] * 1.5).clamped(to: 0.0...1.0))
    }
    // alpha
    colorsComps.append((self.components![3] + 0.4).clamped(to: 0.0...1.0))

    let colorSpace = self.colorSpace ?? CGColorSpaceCreateDeviceRGB()
    return CGColor(colorSpace: colorSpace, components: colorsComps)!
  }
}

/// Draws slider bars, e.g., play slider & volume slider.
/// 
/// In the future, the sliders should be entirely custom, instead of relying on legacy `NSSlider`. Then the knob & slider can be
/// implemented via their own separate `CALayer`s which should enable more optimization opportunities. It's not been tested whether drawing
/// into (possibly cached) `CGImage`s as this class currently does delivers any improved performance (or is even slower)...
class BarFactory {
  // MARK: - Init / Config

  var playBar_Normal:  PlayBarConfScaleSet
  var playBar_Focused:  PlayBarConfScaleSet

  var volBar_Normal: VolBarConfScaleSet
  var volBar_Focused: VolBarConfScaleSet

  let maxPlayBarHeightNeeded: CGFloat
  let maxVolBarHeightNeeded: CGFloat
  let shadowPadding: CGFloat

  private var leftCachedColor: CGColor
  private var rightCachedColor: CGColor

  init(effectiveAppearance: NSAppearance, _ layout: LayoutSpec) {
    // If clear BG, can mostly reuse dark theme, but some things need tweaks (e.g. barColorRight needs extra alpha)
    let hasClearBG = layout.effectiveOSCColorScheme == .clearGradient
    let barAppearance = hasClearBG ? NSAppearance(iinaTheme: .dark)! : effectiveAppearance

    let (barColorLeft, barColorRight) = barAppearance.applyAppearanceFor {
      let barColorLeft: CGColor
      let userSetting: Preference.SliderBarLeftColor = Preference.enum(for: .sliderBarDoneColor)
      switch userSetting {
      case .gray:
        barColorLeft = (hasClearBG ? NSColor.mainSliderBarLeftClearBG : NSColor.mainSliderBarLeft).cgColor
      case .controlAccentColor:
        barColorLeft = NSColor.controlAccentColor.cgColor
      }

      let barColorRight = (hasClearBG ? NSColor.mainSliderBarRightClearBG : NSColor.mainSliderBarRight).cgColor
      return (barColorLeft, barColorRight)
    }

    // I want to vary the curvature based on bar height, but want to avoid drawing bars with different curvature in the same image,
    // which can happen when focusing on a chapter in a multi-chapter video. So: only update the curvature once per image set.
    var cornerCurvature: CGFloat = Preference.bool(for: .roundSliderBarRects) ? 1.0 : 0.0
    func updateCurvature(using baseBarHeight: CGFloat) {
      guard cornerCurvature > 0.0 else { return }
      if baseBarHeight <= Constants.Distance.Slider.reducedCurvatureBarHeightThreshold {
        // At smaller sizes, the rounded effect is less noticeable, so increase to compensate
        cornerCurvature = 0.5
      } else {
        // At larger sizes, too much rounding can hurt the usability of the slider as a measure of quantity.
        cornerCurvature = 0.35
      }
    }
    func cornerRadius(for barHeight: CGFloat) -> CGFloat {
      return (barHeight * cornerCurvature).rounded()
    }

    // CONSTANTS: All in points (not pixels).
    // Make sure these are even numbers! Otherwise bar will be antialiased on non-Retina displays

    // - Secondary Vars - PlaySlider & VolumeSlider both:

    let oscGeo = layout.controlBarGeo
    let barHeight_Normal: CGFloat = oscGeo.sliderBarHeightNormal
    Logger.log.verbose{"OSC slider bar height (normal): \(barHeight_Normal)"}
    updateCurvature(using: barHeight_Normal)
    let barCornerRadius_Normal = cornerRadius(for: barHeight_Normal)

    leftCachedColor = barColorLeft.exaggerated()
    rightCachedColor = barColorRight.exaggerated()

    // - Secondary Vars - PlaySlider:

    // Bar shadow is only drawn when using clear BG style
    let shadowPadding = Constants.Distance.Slider.shadowBlurRadius  // each side of bar!
    self.shadowPadding = shadowPadding

    let chapterGapWidth: CGFloat = (barHeight_Normal * 0.5).rounded()

    // Focused AND is the current chapter, when media has more than 1 chapter:
    let barHeight_FocusedCurrChapter: CGFloat = (barHeight_Normal * Constants.Distance.Slider.unscaledFocusedCurrentChapterHeight_Multiplier).rounded()
    updateCurvature(using: barHeight_FocusedCurrChapter)
    let barCornerRadius_FocusedCurrChapter = cornerRadius(for: barHeight_FocusedCurrChapter)

    /// Focused AND [(has more than 1 chapter, but not the current chapter) OR (only one chapter)]:
    let barHeight_FocusedNonCurrChapter: CGFloat = (barHeight_Normal * Constants.Distance.Slider.unscaledFocusedNonCurrentChapterHeight_Multiplier).rounded()
    let barCornerRadius_FocusedNonCurrChapter = cornerRadius(for: barHeight_FocusedNonCurrChapter)

    let maxPlayBarHeightNeeded = max(barHeight_Normal, barHeight_FocusedCurrChapter, barHeight_FocusedNonCurrChapter)
    self.maxPlayBarHeightNeeded = maxPlayBarHeightNeeded

    // - Secondary Vars - VolumeSlider:

    let barHeight_VolumeAbove100_Left: CGFloat = barHeight_Normal
    let barHeight_VolumeAbove100_Right: CGFloat = (barHeight_VolumeAbove100_Left * 0.5).rounded()
    updateCurvature(using: barHeight_VolumeAbove100_Left) // base on tallest bar height being drawn
    let barCornerRadius_VolumeAbove100_Left = cornerRadius(for: barHeight_VolumeAbove100_Left)
    let barCornerRadius_VolumeAbove100_Right = cornerRadius(for: barHeight_VolumeAbove100_Right)

    let barHeight_Volume_Focused: CGFloat = barHeight_FocusedNonCurrChapter
    let barHeight_Focused_VolumeAbove100_Left: CGFloat = barHeight_FocusedCurrChapter
    let barHeight_Focused_VolumeAbove100_Right: CGFloat = barHeight_Normal
    updateCurvature(using: barHeight_FocusedCurrChapter)
    let barCornerRadius_Volume_Focused = cornerRadius(for: barHeight_Volume_Focused)
    let barCornerRadius_Focused_VolumeAbove100_Left = cornerRadius(for: barHeight_Focused_VolumeAbove100_Left)
    let barCornerRadius_Focused_VolumeAbove100_Right = cornerRadius(for: barHeight_Focused_VolumeAbove100_Right)

    let maxVolBarHeightNeeded = max(barHeight_Normal, barHeight_VolumeAbove100_Left, barHeight_VolumeAbove100_Right,
                                    barHeight_Volume_Focused, barHeight_Focused_VolumeAbove100_Left, barHeight_Focused_VolumeAbove100_Right)
    self.maxVolBarHeightNeeded = maxVolBarHeightNeeded

    // - PlaySlider config sets

    let playNormalLeft = BarConfScaleSet(imgPadding: barImgPadding, imgHeight: barVerticalPaddingTotal + maxPlayBarHeightNeeded,
                                         barHeight: barHeight_Normal, interPillGapWidth: chapterGapWidth,
                                         fillColor: barColorLeft, pillCornerRadius: barCornerRadius_Normal)
    let playNormalRight = playNormalLeft.cloned(fillColor: barColorRight)
    rightCachedColor = barColorRight.exaggerated()

    playBar_Normal =  PlayBarConfScaleSet(currentChapter_Left: playNormalLeft, currentChapter_Right: playNormalRight,
                                          nonCurrentChapter_Left: playNormalLeft, nonCurrentChapter_Right: playNormalRight)

    let focusedCurrChapterLeft = playNormalLeft.cloned(barHeight: barHeight_FocusedCurrChapter,
                                                       pillCornerRadius: barCornerRadius_FocusedCurrChapter)
    let focusedCurrChapterRight = playNormalRight.cloned(barHeight: barHeight_FocusedCurrChapter,
                                                         pillCornerRadius: barCornerRadius_FocusedCurrChapter)
    let nonCurrChapterLeft = playNormalLeft.cloned(barHeight: barHeight_FocusedNonCurrChapter,
                                                   pillCornerRadius: barCornerRadius_FocusedNonCurrChapter)
    let nonCurrChapterRight = playNormalRight.cloned(barHeight: barHeight_FocusedNonCurrChapter,
                                                     pillCornerRadius: barCornerRadius_FocusedNonCurrChapter)
    playBar_Focused =  PlayBarConfScaleSet(currentChapter_Left: focusedCurrChapterLeft, currentChapter_Right: focusedCurrChapterRight,
                                           nonCurrentChapter_Left: nonCurrChapterLeft, nonCurrentChapter_Right: nonCurrChapterRight)

    // - VolumeSlider config sets

    let volumeBelow100_Left = BarConfScaleSet(imgPadding: barImgPadding, imgHeight: barVerticalPaddingTotal + maxVolBarHeightNeeded,
                                              barHeight: barHeight_Normal, interPillGapWidth: 0.0,
                                              fillColor: barColorLeft, pillCornerRadius: barCornerRadius_Normal)
    let volumeBelow100_Right = volumeBelow100_Left.cloned(fillColor: barColorRight)

    let volAbove100_Left_FillColor = volumeBelow100_Left.fillColor.exaggerated()
    let volAbove100_Right_FillColor = volumeBelow100_Right.fillColor // volumeBelow100_Right.fillColor.exaggerated()
    let volumeAbove100_Left = volumeBelow100_Left.cloned(barHeight: barHeight_VolumeAbove100_Left,
                                                         fillColor: volAbove100_Left_FillColor,
                                                         pillCornerRadius: barCornerRadius_VolumeAbove100_Left)
    let volumeAbove100_Right = volumeBelow100_Right.cloned(barHeight: barHeight_VolumeAbove100_Right,
                                                           fillColor: volAbove100_Right_FillColor,
                                                           pillCornerRadius: barCornerRadius_VolumeAbove100_Right)

    volBar_Normal = VolBarConfScaleSet(volumeBelow100_Left: volumeBelow100_Left,
                                       volumeBelow100_Right: volumeBelow100_Right,
                                       volumeAbove100_Left: volumeAbove100_Left,
                                       volumeAbove100_Right: volumeAbove100_Right)

    volBar_Focused = VolBarConfScaleSet(volumeBelow100_Left: volumeBelow100_Left.cloned(barHeight: barHeight_Volume_Focused, pillCornerRadius: barCornerRadius_Volume_Focused),
                                        volumeBelow100_Right: volumeBelow100_Right.cloned(barHeight: barHeight_Volume_Focused, pillCornerRadius: barCornerRadius_Volume_Focused),
                                        volumeAbove100_Left: volumeAbove100_Left.cloned(barHeight: barHeight_Focused_VolumeAbove100_Left, pillCornerRadius: barCornerRadius_Focused_VolumeAbove100_Left),
                                        volumeAbove100_Right: volumeAbove100_Right.cloned(barHeight: barHeight_Focused_VolumeAbove100_Right, pillCornerRadius: barCornerRadius_Focused_VolumeAbove100_Right))
  }

  // MARK: - Play Bar

  /// `barWidth` does not include added leading or trailing margin
  func buildPlayBarImage(useFocusEffect: Bool,
                         barWidth: CGFloat,
                         scaleFactor: CGFloat,
                         knobRect: NSRect,
                         currentValueSec: CGFloat, maxValueSec: CGFloat,
                         currentPreviewTimeSec: Double?,
                         _ chapters: [MPVChapter], cachedRanges: [(Double, Double)]) -> CGImage {
    // - Set up calculations

    let imgConf = (useFocusEffect ? playBar_Focused : playBar_Normal).forImg(scale: scaleFactor, barWidth: barWidth)

    func xForSec(_ sec: CGFloat) -> CGFloat {
      (imgConf.imgPadding + (sec / maxValueSec * imgConf.barWidth)).rounded()
    }
    let currentValuePointX = xForSec(currentValueSec)

    // Start by drawing to the left of the knob, clipping out the knob
    let leftClipMaxX: CGFloat = (knobRect.minX - 1) * scaleFactor

    let barImg = CGImage.buildBitmapImage(width: Int(imgConf.imgWidth), height: Int(imgConf.imgHeight)) { ctx in

      // Note that nothing is drawn for leading knobMarginRadius_Scaled or trailing knobMarginRadius_Scaled.
      // The empty space exists to make image offset calculations consistent (thus easier) between knob & bar images.
      var segsMaxX: [Double] = []
      // currentChapterHover==nil: chapter hover effect not enabled
      var currentChapterHoverX: CGFloat? = nil
      if chapters.count > 0, maxValueSec > 0 {
        if useFocusEffect {
          if let currentPreviewTimeSec {
            // Mouse is hovering & showing Seek Preview: use its X coord
            currentChapterHoverX = xForSec(currentPreviewTimeSec)
          } else {
            // Actively seeking or scrolling: use position of the knob for current chapter
            currentChapterHoverX = currentValuePointX
          }
        }
        segsMaxX = chapters[1...].map{ xForSec($0.startTime) }
      }
      if Logger.isTraceEnabled {
        Logger.log.trace{"ValueX: \(currentValuePointX), CurrChHoverX: \(currentChapterHoverX?.description ?? "nil")"}
      }

      // Add right end of bar (don't forget to subtract left & right padding from img)
      let lastSegMaxX = imgConf.imgWidth - (imgConf.imgPadding * 2)
      segsMaxX.append(lastSegMaxX)

      var currentChapterHover: Int? = nil
      if let currentChapterHoverX {
        for (index, segMaxX) in segsMaxX.enumerated() {
          if currentChapterHoverX <= segMaxX {
            currentChapterHover = index
            break
          }
        }
      }

      var segIndex = 0
      var segMinX = imgConf.imgPadding

      var leftEdge: BarConf.PillEdgeType = .noBorderingPill
      var rightEdge: BarConf.PillEdgeType = .bordersAnotherPill

      // 0: Drawing bar left of knob
      // 1: Drawing last (maybe partial) segment of bar left of knob
      // 2: Drawing bar right of knob
      var leftStatus: Int
      let hasLeft = leftClipMaxX - imgConf.imgPadding > 0.0
      if hasLeft {
        leftStatus = 0
        let leftClipRect = CGRect(x: 0, y: 0,
                                  width: leftClipMaxX,
                                  height: imgConf.imgHeight)
        ctx.clip(to: leftClipRect)
      } else {
        leftStatus = 1
      }

      while segIndex < segsMaxX.count {
        let segMaxX = segsMaxX[segIndex]

        // Need to adjust calculation here to account for trailing img padding:
        let conf: BarConf
        if leftStatus == 0 {
          conf = currentChapterHover == segIndex ? imgConf.currentChapter_Left : imgConf.nonCurrentChapter_Left

          if segMaxX == lastSegMaxX {  // is last pill
            rightEdge = .noBorderingPill
            // May need to split current segment with right
            leftStatus = 1
          } else if segMaxX > leftClipMaxX || segMinX > leftClipMaxX {
            leftStatus = 1
          }
        } else {
          conf = currentChapterHover == segIndex ? imgConf.currentChapter_Right : imgConf.nonCurrentChapter_Right

          if segMaxX == lastSegMaxX {  // is last pill
            rightEdge = .noBorderingPill
          }

          if leftStatus == 1 {
            // Right of knob (or just unfinished progress, if no knob)
            let rightClipMinX = (knobRect.maxX - 1) * scaleFactor
            let rightClipRect = CGRect(x: rightClipMinX, y: 0,
                                       width: imgConf.imgWidth - rightClipMinX,
                                       height: imgConf.imgHeight)
            ctx.resetClip()
            ctx.clip(to: rightClipRect)
            leftStatus = 2
          }
        }

        conf.drawPill(ctx,
                      minX: segMinX, maxX: segMaxX,
                      leftEdge: leftEdge,
                      rightEdge: rightEdge)

        if leftStatus == 1 {
          leftEdge = .noBorderingPill
        } else {
          // Set for all but first pill
          leftEdge = .bordersAnotherPill
          // Advance for next loop
          segIndex += 1
          segMinX = segMaxX
        }
      }

    }  // end first img

    if cachedRanges.isEmpty {
      return barImg  // optimization: skip composite img build
    }

    // Show cached ranges (if enabled).
    // Not sure how efficient this is...

    // First build overlay image which colors all the cached regions
    let cacheImg = CGImage.buildBitmapImage(width: Int(imgConf.imgWidth), height: Int(imgConf.imgHeight)) { ctx in

      // First, just color the cached regions as crude rects which are at least as large as barImg…
      let maxBarHeightNeeded = imgConf.maxBarHeightNeeded
      let minY: CGFloat = (imgConf.imgHeight - maxBarHeightNeeded) * 0.5

      var rectsLeft: [NSRect] = []
      var rectsRight: [NSRect] = []
      for cachedRange in cachedRanges {
        let startX: CGFloat = xForSec(cachedRange.0)
        let endX: CGFloat = xForSec(cachedRange.1)
        if startX > leftClipMaxX {
          rectsRight.append(CGRect(x: startX, y: minY,
                                   width: endX - startX, height: maxBarHeightNeeded))
        } else if endX > leftClipMaxX {
          rectsLeft.append(CGRect(x: startX, y: minY,
                                  width: leftClipMaxX - startX, height: maxBarHeightNeeded))

          let start2ndX = leftClipMaxX
          rectsRight.append(CGRect(x: start2ndX, y: minY,
                                   width: endX - start2ndX, height: maxBarHeightNeeded))
        } else {
          rectsLeft.append(CGRect(x: startX, y: minY,
                                  width: endX - startX, height: maxBarHeightNeeded))
        }
      }

      ctx.setFillColor(leftCachedColor)
      ctx.fill(rectsLeft)
      ctx.setFillColor(rightCachedColor)
      ctx.fill(rectsRight)

      // Now use barImg as a mask, so that crude rects above are trimmed to match its silhoulette:
      ctx.setBlendMode(.destinationIn)
      ctx.draw(barImg, in: CGRect(origin: .zero, size: imgConf.imgSize))
    }

    let compositeImg = CGImage.buildBitmapImage(width: barImg.width, height: barImg.height) { ctx in
      let barFrame = CGRect(origin: CGPoint(x: 0, y: 0), size: barImg.size())

      ctx.setBlendMode(.normal)
      ctx.draw(barImg, in: barFrame)

      // Paste cacheImg over barImg:
      ctx.setBlendMode(.overlay)
      ctx.draw(cacheImg, in: barFrame)
    }

    return compositeImg
  }

  // MARK: - Volume Bar

  func buildVolumeBarImage(useFocusEffect: Bool,
                           barWidth: CGFloat,
                           scaleFactor: CGFloat,
                           knobRect: NSRect,
                           currentValue: Double, maxValue: Double,
                           currentPreviewValue: CGFloat? = nil) -> CGImage {

    // - Set up calculations
    let conf = (useFocusEffect ? volBar_Focused : volBar_Normal).forImg(scale: scaleFactor, barWidth: barWidth)

    let currentValueRatio = currentValue / maxValue
    let currentValuePointX = (conf.imgPadding + (currentValueRatio * conf.barWidth)).rounded()

    // Determine clipping rects (pixel whitelists)
    let leftClipMaxX: CGFloat
    let rightClipMinX: CGFloat
    let hasSpaceForKnob = knobRect.width > 0.0
    if useFocusEffect && hasSpaceForKnob {
      // - Will clip out the knob
      leftClipMaxX = (knobRect.minX - 1) * scaleFactor
      rightClipMinX = leftClipMaxX + (knobRect.width * scaleFactor)
    } else {
      // No knob
      leftClipMaxX = currentValuePointX
      rightClipMinX = currentValuePointX
    }

    let hasLeft = leftClipMaxX - conf.imgPadding > 0.0
    let hasRight = rightClipMinX + conf.imgPadding < conf.imgWidth

    // If volume can exceed 100%, let's draw the part of the bar which is >100% differently
    let vol100PercentPointX = (conf.imgPadding + ((100.0 / maxValue) * conf.barWidth)).rounded()
    let barMaxX = conf.barMaxX

    let barImg = CGImage.buildBitmapImage(width: Int(conf.imgWidth), height: Int(conf.imgHeight)) { ctx in

      func drawEntireBar(_ barConf: BarConf, clipMinX: CGFloat, clipMaxX: CGFloat) {
        ctx.resetClip()
        ctx.clip(to: CGRect(x: clipMinX, y: 0,
                            width: clipMaxX - clipMinX,
                            height: barConf.imgHeight))

        barConf.addPillPath(ctx, minX: barConf.barMinX,
                            maxX: barMaxX,
                            leftEdge: .noBorderingPill,
                            rightEdge: .noBorderingPill)
        ctx.clip()

        barConf.drawPill(ctx,
                         minX: barConf.barMinX,
                         maxX: barMaxX,
                         leftEdge: .noBorderingPill,
                         rightEdge: .noBorderingPill)
      }

      var barConf = conf.below100_Left

      if hasLeft {  // Left of knob (i.e. "completed" section of bar)
        var minX = 0.0

        if vol100PercentPointX < leftClipMaxX {
          // Current volume > 100%. Finish drawing (< 100%) first.
          drawEntireBar(barConf, clipMinX: minX, clipMaxX: vol100PercentPointX)
          // Update for next segment:
          minX = vol100PercentPointX
          barConf = conf.above100_Left
        }

        drawEntireBar(barConf, clipMinX: minX, clipMaxX: leftClipMaxX)
      }

      if hasRight {  // Right of knob
        var minX = rightClipMinX
        if vol100PercentPointX <= rightClipMinX {
          barConf = conf.above100_Right
        } else {
          barConf = conf.below100_Right

          if vol100PercentPointX > rightClipMinX && vol100PercentPointX < conf.imgWidth {
            drawEntireBar(barConf, clipMinX: minX, clipMaxX: vol100PercentPointX)
            // Update for next segment:
            minX = vol100PercentPointX
            barConf = conf.above100_Right
          }
        }

        drawEntireBar(barConf, clipMinX: minX, clipMaxX: conf.imgWidth)
      }
    }

    return barImg
  }  // end func buildVolumeBarImage

  // MARK: - Other API functions

  static func heightNeeded(tallestBarHeight: CGFloat) -> CGFloat {
    return barVerticalPaddingTotal + tallestBarHeight
  }

  /// Measured in points, not pixels!
  private func imageRect(in drawRect: CGRect, tallestBarHeight: CGFloat) -> CGRect {
    let imgHeight = BarFactory.heightNeeded(tallestBarHeight: tallestBarHeight)
    // can be negative:
    let spareHeight = drawRect.height - imgHeight
    let barImgPadding = barImgPadding
    return CGRect(x: drawRect.origin.x - barImgPadding,
                  y: drawRect.origin.y + (spareHeight * 0.5),
                  width: drawRect.width + (2 * barImgPadding), height: imgHeight)
  }

  func drawBar(_ barImg: CGImage, in barRect: NSRect, scaleFactor: CGFloat,
               tallestBarHeight: CGFloat, drawShadow: Bool) {
    var drawRect = imageRect(in: barRect, tallestBarHeight: tallestBarHeight)
    if #unavailable(macOS 11) {
      drawRect = NSRect(x: drawRect.origin.x,
                        y: drawRect.origin.y + 1,
                        width: drawRect.width,
                        height: drawRect.height - 2)
    }

    let ctx = NSGraphicsContext.current!.cgContext

    if drawShadow {
      let shadowPadding_Scaled = shadowPadding * scaleFactor
      ctx.setShadow(offset: CGSize(width: 0, height: 0), blur: shadowPadding_Scaled)
      ctx.beginTransparencyLayer(auxiliaryInfo: nil)
    }
    ctx.draw(barImg, in: drawRect)
    if drawShadow {
      ctx.endTransparencyLayer()
    }
  }

}
