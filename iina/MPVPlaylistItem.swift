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

  var isNetworkResource: Bool { !url.isFileURL }

  init(url: URL) {
    self.url = url
  }
}
