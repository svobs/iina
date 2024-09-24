//
//  MPVPlaylistItem.swift
//  iina
//
//  Created by lhc on 23/8/16.
//  Copyright © 2016 lhc. All rights reserved.
//

import Foundation

class MPVPlaylistItem {

  /** Equivalent to `Playback.url(fromPath: mpvFilename)` */
  var url: URL

  /** Title or the real filename */
  var displayName: String {
    let urlPath = Playback.path(from: url)
    return isNetworkResource ? urlPath : NSString(string: urlPath).lastPathComponent
  }

  // Too inefficient and infrequently used. Just set to false for now so it doesn't break JavascriptAPI
  var isCurrent: Bool { false }
  var isPlaying: Bool { false }
  var isNetworkResource: Bool { !url.isFileURL }

  var title: String?

  init(url: URL, title: String?) {
    self.url = url
    self.title = title
  }
}
