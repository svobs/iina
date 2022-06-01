//
//  UITestUtil.swift
//  IINA-UI-Tests
//
//  Created by Matthew Svoboda on 2022.05.31.
//  Copyright © 2022 lhc. All rights reserved.
//

import XCTest
import Foundation

extension XCUIApplication {
  func setPref(_ prefName: String, _ prefValue: String) {
    launchArguments += ["-\(prefName)", prefValue]
  }

  func setPrefs(_ prefDict: [String: String]) {
    for (prefName, prefValue) in prefDict {
      launchArguments += ["-\(prefName)", prefValue]
    }
  }
}

extension XCTestCase {
  public func getBundleFilePath(_ filename: String) -> String {
    let filenameURL = URL(fileURLWithPath: filename)
    let testBundle = Bundle(for: type(of: self))
    let path = testBundle.path(forResource: String(filenameURL.pathExtension), ofType: filenameURL.deletingPathExtension().lastPathComponent)
    XCTAssertNotNil(path)
    return path!
  }
}
