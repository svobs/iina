//
//  KeyboardNavTest.swift
//  IINA UI Tests
//
//  Created by Matt Svoboda on 2022.05.31.
//  Copyright © 2022 lhc. All rights reserved.
//

import XCTest

class InitialWindow_KeyNavigationTests: XCTestCase {
  var userDefaults: UserDefaults?
  let userDefaultsSuiteName = "TestDefaults"

  override func setUpWithError() throws {
    continueAfterFailure = false
  }

  // Opens IINA & clears playback history - then quits
  private func clearRecentDocumentsInIINA() {
    let app = XCUIApplication()
    app.launch()
    let welcomeWindow = app/*@START_MENU_TOKEN@*/.windows.containing(.image, identifier:"iina arrow").element/*[[".windows.containing(.button, identifier:XCUIIdentifierMinimizeWindow).element",".windows.containing(.button, identifier:XCUIIdentifierZoomWindow).element",".windows.containing(.button, identifier:XCUIIdentifierCloseWindow).element",".windows.containing(.image, identifier:\"history\").element",".windows.containing(.image, identifier:\"iina arrow\").element"],[[[-1,4],[-1,3],[-1,2],[-1,1],[-1,0]]],[0]]@END_MENU_TOKEN@*/
    welcomeWindow.typeKey(",", modifierFlags:.command)

    let preferencesWindow = app.windows["Preferences"]
    preferencesWindow/*@START_MENU_TOKEN@*/.tables.staticTexts["Utilities"]/*[[".scrollViews.tables",".tableRows",".cells.staticTexts[\"Utilities\"]",".staticTexts[\"Utilities\"]",".tables"],[[[-1,4,1],[-1,0,1]],[[-1,3],[-1,2],[-1,1,2]],[[-1,3],[-1,2]]],[0,0]]@END_MENU_TOKEN@*/.click()
    preferencesWindow/*@START_MENU_TOKEN@*/.buttons["FunctionalButtonClearHistory"]/*[[".scrollViews",".buttons[\"Clear Playback History…\"]",".buttons[\"FunctionalButtonClearHistory\"]"],[[[-1,2],[-1,1],[-1,0,1]],[[-1,2],[-1,1]]],[0]]@END_MENU_TOKEN@*/.click()
    preferencesWindow.sheets["alert"].buttons["OK"].click()
    preferencesWindow.buttons[XCUIIdentifierCloseWindow].click()
    welcomeWindow.typeKey("q", modifierFlags:.command)
  }

  override func tearDownWithError() throws {
    // Put teardown code here. This method is called after the invocation of each test method in the class.
  }

  func testWithNoRecents() throws {
    clearRecentDocumentsInIINA()

    let app = XCUIApplication()
    app.launch()
    let welcomeWindow = app/*@START_MENU_TOKEN@*/.windows.containing(.image, identifier:"iina arrow").element/*[[".windows.containing(.button, identifier:XCUIIdentifierMinimizeWindow).element",".windows.containing(.button, identifier:XCUIIdentifierZoomWindow).element",".windows.containing(.button, identifier:XCUIIdentifierCloseWindow).element",".windows.containing(.image, identifier:\"iina arrow\").element"],[[[-1,3],[-1,2],[-1,1],[-1,0]]],[0]]@END_MENU_TOKEN@*/
    welcomeWindow.typeKey(.downArrow, modifierFlags:.function)
    welcomeWindow.typeKey(.upArrow, modifierFlags:.function)
    welcomeWindow.typeText("\r")
    app.windows.images["iina arrow"].click()
    welcomeWindow.typeKey("q", modifierFlags:.command)

  }

  func testKeyNav() throws {
    let path = getBundleFilePath("filename.jpg")

    let app = XCUIApplication()
    //    var prefs: [String: String] =
    app.setPrefs(
      ["osdAutoHideTimeout" : "104",
       "recordRecentFiles" : "true",
       "resumeLastPosition" : "true",
       "iinaLastPlayedFilePath": "/tmp/file"
      ])
    app.setPref("osdAutoHideTimeout", "104")
    app.launch()
    let menuBarsQuery = app.menuBars
    menuBarsQuery.menuBarItems["IINA"].click()
    menuBarsQuery/*@START_MENU_TOKEN@*/.menuItems["Preferences…"]/*[[".menuBarItems[\"IINA\"]",".menus.menuItems[\"Preferences…\"]",".menuItems[\"Preferences…\"]"],[[[-1,2],[-1,1],[-1,0,1]],[[-1,2],[-1,1]]],[0]]@END_MENU_TOKEN@*/.click()
    let preferencesWindow = app.windows["Preferences"]
    preferencesWindow/*@START_MENU_TOKEN@*/.tables.staticTexts["UI"]/*[[".scrollViews.tables",".tableRows",".cells.staticTexts[\"UI\"]",".staticTexts[\"UI\"]",".tables"],[[[-1,4,1],[-1,0,1]],[[-1,3],[-1,2],[-1,1,2]],[[-1,3],[-1,2]]],[0,0]]@END_MENU_TOKEN@*/.click()

    preferencesWindow/*@START_MENU_TOKEN@*/.tables.containing(.tableColumn, identifier:"AutomaticTableColumnIdentifier.0").element/*[[".scrollViews.tables.containing(.tableColumn, identifier:\"AutomaticTableColumnIdentifier.0\").element",".tables.containing(.tableColumn, identifier:\"AutomaticTableColumnIdentifier.0\").element"],[[[-1,1],[-1,0]]],[0]]@END_MENU_TOKEN@*/.typeKey("q", modifierFlags:.command)


  }

  func testLaunchPerformance() throws {
    if #available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 7.0, *) {
      // This measures how long it takes to launch your application.
      measure(metrics: [XCTApplicationLaunchMetric()]) {
        XCUIApplication().launch()
      }
    }
  }
}
