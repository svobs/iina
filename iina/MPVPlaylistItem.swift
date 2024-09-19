//
//  MPVPlaylistItem.swift
//  iina
//
//  Created by lhc on 23/8/16.
//  Copyright © 2016 lhc. All rights reserved.
//

import Foundation

class MPVPlaylistItem {

  /** Actually this is the URL path. Using `filename` to conform mpv API's naming. */
  var filename: String

  /** Title or the real filename */
  var filenameForDisplay: String {
    return isNetworkResource ? filename : NSString(string: filename).lastPathComponent
  }

  // Too inefficient and infrequently used. Just set to false for now so it doesn't break JavascriptAPI
  var isCurrent: Bool { return false }
  var isPlaying: Bool { return false }
  var isNetworkResource: Bool

  var title: String?

  init(filename: String, title: String?) {
    self.filename = filename
    self.title = title
    self.isNetworkResource = Regex.url.matches(filename)
  }
}
