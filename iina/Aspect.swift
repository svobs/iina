//
//  Aspect.swift
//  iina
//
//  Created by lhc on 2/9/16.
//  Copyright © 2016 lhc. All rights reserved.
//

import Cocoa

class Aspect: NSObject {
  static func mpvPrecision(of aspectRatio: CGFloat) -> CGFloat {
    return CGFloat(round(aspectRatio * 100.0)) * 0.01
  }

  static func isValid(_ string: String) -> Bool {
    return Aspect(string: string) != nil
  }

  private var size: NSSize!

  var width: CGFloat {
    get {
      return size.width
    }
    set {
      size.width = newValue
    }
  }

  var height: CGFloat {
    get {
      return size.height
    }
    set {
      size.height = newValue
    }
  }

  var value: CGFloat {
    get {
      return Aspect.mpvPrecision(of: size.width / size.height)
    }
  }

  init(size: NSSize) {
    self.size = size
  }

  init(width: CGFloat, height: CGFloat) {
    self.size = NSMakeSize(width, height)
  }

  init?(string: String) {
    if Regex.aspect.matches(string) {
      let wh = string.components(separatedBy: ":")
      if let cropW = Float(wh[0]), let cropH = Float(wh[1]) {
        self.size = NSMakeSize(CGFloat(cropW), CGFloat(cropH))
      }
    } else if let ratio = Float(string), ratio > 0.0 {
      self.size = NSMakeSize(CGFloat(ratio), CGFloat(1))
    } else {
      return nil
    }
  }
}
