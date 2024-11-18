//
//  MarginQuad.swift
//  iina
//
//  Created by Matt Svoboda on 5/20/24.
//  Copyright © 2024 lhc. All rights reserved.
//

import Foundation

/// A data structure which contains the sizes of 4 1-dimensional margins
struct MarginQuad: Equatable, CustomStringConvertible {
  let top: CGFloat
  let trailing: CGFloat
  let bottom: CGFloat
  let leading: CGFloat

  var totalWidth: CGFloat {
    return leading + trailing
  }

  var totalHeight: CGFloat {
    return top + bottom
  }

  var totalSize: CGSize {
    return CGSize(width: totalWidth, height: totalHeight)
  }

  var description: String {
    return "(↑:\(top.logStr) →:\(trailing.logStr) ↓:\(bottom.logStr) ←:\(leading.logStr))"
  }

  init(top: CGFloat = 0, trailing: CGFloat = 0, bottom: CGFloat = 0, leading: CGFloat = 0) {
    self.top = top
    self.trailing = trailing
    self.bottom = bottom
    self.leading = leading
  }

  func clone(top: CGFloat? = nil, trailing: CGFloat? = nil,
             bottom: CGFloat? = nil, leading: CGFloat? = nil) -> MarginQuad {
    return MarginQuad(top: top ?? self.top,
                      trailing: trailing ?? self.trailing,
                      bottom: bottom ?? self.bottom,
                      leading: leading ?? self.leading)
  }

  func addingTo(top: CGFloat = 0, trailing: CGFloat = 0,  bottom: CGFloat = 0,  leading: CGFloat = 0) -> MarginQuad {
    return MarginQuad(top: self.top + top,
                      trailing: self.trailing + trailing,
                      bottom: self.bottom + bottom,
                      leading: self.leading + leading)
  }

  func subtractingFrom( top: CGFloat = 0,  trailing: CGFloat = 0, bottom: CGFloat = 0,  leading: CGFloat = 0) -> MarginQuad {
    return addingTo(top: -top, trailing: -trailing, bottom: -bottom, leading: -leading)
  }

  static let zero = MarginQuad(top: 0, trailing: 0, bottom: 0, leading: 0)
}
