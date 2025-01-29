//
//  BarFactoryUtil.swift
//  iina
//
//  Created by Matt Svoboda on 2024-12-19.
//

extension BarFactory {

  // MARK: - Support Classes

  struct BarConf {
    let scaleFactor: CGFloat

    let imgPadding: CGFloat
    /// `imgHeight` is independent of `barHeight`
    let imgHeight: CGFloat
    let barHeight: CGFloat
    let interPillGapWidth: CGFloat

    let fillColor: CGColor
    let pillCornerRadius: CGFloat

    var barMinY: CGFloat { (imgHeight - barHeight) * 0.5 }
    var barMinX: CGFloat { imgPadding }

    /// Corner radius will be overridden to `0` if `PK.roundRectSliderBars` is true
    init(scaleFactor: CGFloat, imgPadding: CGFloat, imgHeight: CGFloat, barHeight: CGFloat, interPillGapWidth: CGFloat,
         fillColor: CGColor, pillCornerRadius: CGFloat) {
      self.scaleFactor = scaleFactor
      self.imgPadding = imgPadding
      self.imgHeight = imgHeight
      self.barHeight = barHeight
      self.interPillGapWidth = interPillGapWidth
      self.fillColor = fillColor
      self.pillCornerRadius = pillCornerRadius
    }

    func rescaled(to newScaleFactor: CGFloat) -> BarConf {
      let scaleRatio = newScaleFactor / scaleFactor
      return BarConf(
        scaleFactor: newScaleFactor,
        imgPadding: imgPadding * scaleRatio,
        imgHeight: imgHeight * scaleRatio,
        barHeight: barHeight * scaleRatio,
        interPillGapWidth: interPillGapWidth * scaleRatio,
        fillColor: fillColor,
        pillCornerRadius: pillCornerRadius * scaleRatio
      )
    }

    func cloned(imgPadding: CGFloat? = nil,
                imgHeight: CGFloat? = nil,
                barHeight: CGFloat? = nil,
                interPillGapWidth: CGFloat? = nil,
                fillColor: CGColor? = nil,
                pillCornerRadius: CGFloat? = nil) -> BarConf {
      BarConf(
        scaleFactor: scaleFactor,
        imgPadding: imgPadding ?? self.imgPadding,
        imgHeight: imgHeight ?? self.imgHeight,
        barHeight: barHeight ?? self.barHeight,
        interPillGapWidth: interPillGapWidth ?? self.interPillGapWidth,
        fillColor: fillColor ?? self.fillColor,
        pillCornerRadius: pillCornerRadius ?? self.pillCornerRadius)
    }

    // MARK: - CoreGraphics Drawing

    enum PillEdgeType {
      case squareClip
      /// Rounded edge. Needs gap
      case bordersAnotherPill
      /// Rounded edge. No gap
      case noBorderingPill
    }

    /// Adds a pill shape to the given `CGContext`.
    func addPillPath(_ ctx: CGContext, minX: CGFloat, maxX: CGFloat,
                     leftEdge: PillEdgeType, rightEdge: PillEdgeType) {

      ctx.beginPath()
      var adjMinX: CGFloat = minX
      switch leftEdge {
      case .squareClip:
        /// Extend the path left outside of the clip rect by `pillCornerRadius` so that the rounded part gets clipped out,
        /// leaving a square edge instead of rounded
        adjMinX -= self.pillCornerRadius
      case .bordersAnotherPill:
        // There was a prev pill. Start the path a little further right for the second half of the gap
        adjMinX += self.interPillGapWidth * 0.5
      case .noBorderingPill:
        // No preceding pill. No need to adjust edge bound
        break
      }

      var adjMaxX: CGFloat = maxX
      switch rightEdge {
      case .squareClip:
        adjMaxX += self.pillCornerRadius
      case .bordersAnotherPill:
        adjMaxX -= self.interPillGapWidth * 0.5
      case .noBorderingPill:
        break
      }
      let barMinY = barMinY
      let segment = CGRect(x: adjMinX, y: barMinY,
                           width: adjMaxX - adjMinX, height: self.barHeight)
      let path: CGPath
      if self.pillCornerRadius > 0.0 {
        path = CGPath(roundedRect: segment, cornerWidth: self.pillCornerRadius, cornerHeight: self.pillCornerRadius, transform: nil)
      } else {
        path = CGPath(rect: segment, transform: nil)
      }
      ctx.addPath(path)
    }

    /// Draws a single bar segment as rounded rect (pill), using specified gap between pills. Each gap is divided into 2 halves,
    /// with the leading half stealing its width from the pill before it, and the trailing half subtracting width from the pill after it.
    func drawPill(_ ctx: CGContext, minX: CGFloat, maxX: CGFloat,
                  leftEdge: PillEdgeType, rightEdge: PillEdgeType) {
      addPillPath(ctx, minX: minX, maxX: maxX, leftEdge: leftEdge, rightEdge: rightEdge)
      ctx.setFillColor(fillColor)
      ctx.fillPath()
    }

  }  /// end `struct BarConf`


  struct BarConfScaleSet {
    let x1: BarConf
    let x2: BarConf

    init(x1: BarConf, x2: BarConf) {
      self.x1 = x1
      self.x2 = x2
    }

    init(imgPadding: CGFloat, imgHeight: CGFloat, barHeight: CGFloat, interPillGapWidth: CGFloat,
         fillColor: CGColor, pillCornerRadius: CGFloat) {
      let x1 = BarConf(scaleFactor: 1.0, imgPadding: imgPadding, imgHeight: imgHeight, barHeight: barHeight,
                       interPillGapWidth: interPillGapWidth, fillColor: fillColor, pillCornerRadius: pillCornerRadius)
      self.x1 = x1
      self.x2 = x1.rescaled(to: 2.0)
    }

    func cloned(imgPadding: CGFloat? = nil,
                imgHeight: CGFloat? = nil,
                barHeight: CGFloat? = nil,
                interPillGapWidth: CGFloat? = nil,
                fillColor: CGColor? = nil,
                pillCornerRadius: CGFloat? = nil) -> BarConfScaleSet {
      let x1New = x1.cloned(imgPadding: imgPadding, imgHeight: imgHeight, barHeight: barHeight, interPillGapWidth: interPillGapWidth,
                            fillColor: fillColor, pillCornerRadius: pillCornerRadius)
      let x2New = x1New.rescaled(to: 2.0)
      return BarConfScaleSet(x1: x1New, x2: x2New)
    }

    var fillColor: CGColor { x1.fillColor }

    func getScale(_ scale: CGFloat) -> BarConf {
      switch scale {
      case 1.0:
        return x1
      case 2.0:
        return x2
      default:
        fatalError("Unimplemented scale: \(scale)")
      }
    }
  }

  /// - Current vs Other Chapter?
  /// - Focused vs Not Focused?
  struct PlayBarConfScaleSet {
    let currentChapter_Left: BarConfScaleSet
    let currentChapter_Right: BarConfScaleSet

    let nonCurrentChapter_Left: BarConfScaleSet
    let nonCurrentChapter_Right: BarConfScaleSet

    /// `scale` should match `backingScaleFactor` from the current screen.
    /// This will either be `2.0` for Retina displays, or `1.0` for traditional displays.
    func forImg(scale: CGFloat, barWidth: CGFloat) -> PlayBarImgConf {
      let scaledConf = currentChapter_Left.getScale(scale)
      let imgWidth = (barWidth * scale) + (2 * scaledConf.imgPadding)
      let imgSize = CGSize(width: imgWidth, height: scaledConf.imgHeight)
      return PlayBarImgConf(currentChapter_Left: scaledConf,
                            currentChapter_Right: currentChapter_Right.getScale(scale),
                            nonCurrentChapter_Left: nonCurrentChapter_Left.getScale(scale),
                            nonCurrentChapter_Right: nonCurrentChapter_Right.getScale(scale),
                            imgSize: imgSize)
    }
  }

  struct PlayBarImgConf {
    let currentChapter_Left: BarConf
    let currentChapter_Right: BarConf

    let nonCurrentChapter_Left: BarConf
    let nonCurrentChapter_Right: BarConf

    let imgSize: CGSize

    var barWidth: CGFloat {
      imgWidth - (2 * imgPadding)
    }
    var imgPadding: CGFloat { currentChapter_Left.imgPadding }
    var imgHeight: CGFloat { imgSize.height }
    var imgWidth: CGFloat { imgSize.width }

    var maxBarHeightNeeded: CGFloat {
      max(currentChapter_Left.barHeight, currentChapter_Right.barHeight,
          nonCurrentChapter_Left.barHeight, nonCurrentChapter_Right.barHeight) }
  }

  struct VolBarConfScaleSet {
    var volumeBelow100_Left: BarConfScaleSet
    var volumeBelow100_Right: BarConfScaleSet

    var volumeAbove100_Left: BarConfScaleSet
    var volumeAbove100_Right: BarConfScaleSet

    /// `scale` should match `backingScaleFactor` from the current screen.
    /// This will either be `2.0` for Retina displays, or `1.0` for traditional displays.
    func forImg(scale: CGFloat, barWidth: CGFloat) -> VolBarImgConf {
      let below100Left = volumeBelow100_Left.getScale(scale)
      let imgWidth = (barWidth * scale) + (2 * below100Left.imgPadding)
      let imgSize = CGSize(width: imgWidth, height: below100Left.imgHeight)
      return VolBarImgConf(below100_Left: below100Left,
                           below100_Right: volumeBelow100_Right.getScale(scale),
                           above100_Left: volumeAbove100_Left.getScale(scale),
                           above100_Right: volumeAbove100_Right.getScale(scale),
                           imgSize: imgSize)
    }

  }

  /// - Current vs Other Chapter?
  /// - Focused vs Not Focused?
  struct VolBarImgConf {
    let below100_Left: BarConf
    let below100_Right: BarConf

    let above100_Left: BarConf
    let above100_Right: BarConf

    let imgSize: CGSize

    var barWidth: CGFloat {
      imgWidth - (2 * imgPadding)
    }
    var imgPadding: CGFloat { below100_Left.imgPadding }
    var imgHeight: CGFloat { imgSize.height }
    var imgWidth: CGFloat { imgSize.width }

    var barMinX: CGFloat { imgPadding }
    var barMaxX: CGFloat { imgWidth - (imgPadding * 2) }
  }


}
