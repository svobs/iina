//
//  LegacyMigration.swift
//  iina
//
//  Created by Matt Svoboda on 11/27/23.
//  Copyright © 2023 lhc. All rights reserved.
//

import Foundation

class LegacyMigration {

  static func migrateLegacyPreferences() {
    // Nothing to do at present. This class was never really needed because IINA Advance 1.0 ended up using a different
    // .plist file which never used the legacy pref entries for color which IINA used.
    //
    // Will keep this file, however. Will probably migrate playback history in the future.
  }

}
