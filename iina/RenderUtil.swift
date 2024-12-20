//
//  RenderUtil.swift
//  iina
//
//  Created by Matt Svoboda on 2024-12-19.
//  Copyright © 2024 lhc. All rights reserved.
//

extension RenderCache {

  enum PillEdgeType {
    case squareClip
    /// Rounded edge. Needs gap
    case bordersAnotherPill
    /// Rounded edge. No gap
    case noBorderingPill
  }

  /// Draws a single bar segment as rounded rect (pill), using specified gap between pills. Each gap is divided into 2 halves,
  /// with the leading half stealing its width from the pill before it, and the trailing half subtracting width from the pill after it.
  func drawPill(_ cgc: CGContext, _ fillColor: CGColor, minX: CGFloat, maxX: CGFloat, interPillGapWidth: CGFloat, height: CGFloat,
                leftEdge: PillEdgeType, rightEdge: PillEdgeType) {
    addPillPath(cgc, minX: minX, maxX: maxX, interPillGapWidth: interPillGapWidth, height: height, leftEdge: leftEdge, rightEdge: rightEdge)
    cgc.setFillColor(fillColor)
    cgc.fillPath()
  }

  func addPillPath(_ cgc: CGContext, minX: CGFloat, maxX: CGFloat, interPillGapWidth: CGFloat, height: CGFloat,
                leftEdge: PillEdgeType, rightEdge: PillEdgeType) {
    let outerPaddingScaled = RenderCache.shared.barMarginRadius_Scaled
    let cornerRadius_Scaled = RenderCache.shared.barCornerRadius_Scaled

    cgc.beginPath()
    var adjMinX: CGFloat = minX
    switch leftEdge {
    case .squareClip:
      // Extend the path left outside of the clip rect by `cornerRadius_Scaled` so that the rounded part gets clipped out,
      // leaving a square edge instead of rounded
      adjMinX -= cornerRadius_Scaled
    case .bordersAnotherPill:
      // There was a prev pill. Start the path a little further right for the second half of the gap
      adjMinX += interPillGapWidth * 0.5
    case .noBorderingPill:
      // No preceding pill. No need to adjust edge bound
      break
    }

    var adjMaxX: CGFloat = maxX
    switch rightEdge {
    case .squareClip:
      adjMaxX += cornerRadius_Scaled
    case .bordersAnotherPill:
      adjMaxX -= interPillGapWidth * 0.5
    case .noBorderingPill:
      break
    }
    let segment = CGRect(x: adjMinX, y: outerPaddingScaled,
                         width: adjMaxX - adjMinX, height: height)
    cgc.addPath(CGPath(roundedRect: segment, cornerWidth:  cornerRadius_Scaled, cornerHeight:  cornerRadius_Scaled, transform: nil))
  }
}
