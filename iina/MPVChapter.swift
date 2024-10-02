//
//  MPVChapter.swift
//  iina
//
//  Created by lhc on 29/8/16.
//  Copyright © 2016 lhc. All rights reserved.
//

import Foundation

class MPVChapter {

  private var privTitle: String?
  var title: String {
    get {
      return privTitle ?? "\(Constants.String.chapter) \(index)"
    }
  }
  var startTime: Double
  var index: Int

  init(title: String?, startTime: Double, index: Int) {
    self.privTitle = title
    self.startTime = startTime
    self.index = index
  }

}
