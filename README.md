<p align="center">
<img height="256" src="https://github.com/iina/iina/raw/master/iina/Assets.xcassets/AppIcon.appiconset/iina-icon-256.png">
</p>

<h1 align="center">IINA Advance</h1>

<p align="center"><b><a href="https://github.com/iina/iina">IINA</a></b> is the modern video player for macOS.</p>
<p align="center"><b>Advance</b>, as in, <i>advance preview</i> of new or experimental features. Or maybe an attempt to <i>advance</i> IINA development more rapidly.</p>

---
## Major new features

* Can restore all its open windows and state when reopening the app.
* A new player window layout system, allowing for new modes such as showing the controller and sidebars "outside" the video, the ability to expand the window to any size, and much more. Much effort has gone into smoothing out animations so that switching between various modes (and window handling in general) should be very smooth.
* Ability to resize thumbnails, and improved thumbnail handling.
* A massive rewrite of the key bindings system. Adds support for key sequences and dynamic bindings from Lua scripts, and integrates all the other sources of key bindings such as menu items and filter shortcuts. Enhances the Key Bindings editor with copy/paste, undo/redo, drag & drop, color coding for conflict detection and more.
* Tons of bug fixes and enhancements, and hopefully an overall smoother experience.

Stable binaries with more detailed change info can be found on the <a href="https://github.com/svobs/iina-advance/releases/">Releases</a> page.

## Note about reusing previous settings
At present, IINA Advance shares most of the same settings as IINA, and each can share the same settings files without harming the other's. However, because the two apps have different bundle IDs, they store their settings in separate locations and do not share them.

For those who have been using IINA previously and want to copy over their settings, history, and other state, copy each location in the first column to the location in the second column:

|                       | IINA                                                 | IINA Advance                                      |
|-----------------------|------------------------------------------------------|---------------------------------------------------|
| Primary settings file | `~/Library/Preferences/com.colliderli.iina.plist`    | `~/Library/Preferences/com.iina-advance.plist`    |
| Other support files   | `~/Library/Application Support/com.colliderli.iina` | `~/Library/Application Support/com.iina-advance` |

## Downloading

You can get IINA through several sources. For the latest stable and beta releases, visit the [GitHub release page](https://github.com/iina/iina/releases) or the [IINA official website](https://iina.io/). If you want to try out the latest features and improvements before they are officially released, you can download the nightly builds from our [Nightly Download Page](https://iina.io/nightly/).

> [!IMPORTANT]
> Nightly builds are generated by GitHub automatically for every commits, which might be buggy and unusable. If you find a bug, please follow the [contributing section](#Contributing) and file an issue.

## Building
*(unchanged from the upstream IINA project)*

IINA uses mpv for media playback. To build IINA, you can either fetch copies of these libraries we have already built (using the instructions below) or build them yourself by skipping to [these instructions](#building-mpv-manually).

### Using the pre-compiled libraries

1. Download pre-compiled libraries by running

```console
./other/download_libs.sh
```

  - Tips:
    - Change the URL in the shell script if you want to download architecture-specific binaries. By default, it will download the universal ones. You can download other binaries by using `--arch <ARCH>` (universal, arm64, or amd64).
    - The script downloads files using parallel downloads to speed up the process (5 parallel downloads by default). You can change this by using `--parallel <X>` (from 1 to...).
    - If you want to build an older IINA version, make sure to download the corresponding dylibs. For example, `https://iina.io/dylibs/1.2.0/universal/fileList.txt`.

2. Open iina.xcodeproj in the [latest public version of Xcode](https://apps.apple.com/app/xcode/id497799835). *IINA may not build if you use any other version.*

3. Build the project.

### Building mpv manually

1. Build your own copy of mpv. If you're using a package manager to manage dependencies, the steps below outline the process.

	#### With Homebrew

	Use our tap as it passes in the correct flags to mpv's configure script:

	```console
	brew tap iina/homebrew-mpv-iina
	brew install mpv-iina
	```

	#### With MacPorts

	Pass in these flags when installing:

	```console
	port install mpv +uchardet -bundle -rubberband configure.args="--enable-libmpv-shared --enable-lua --enable-libarchive --enable-libbluray --disable-swift --disable-rubberband"
	```

2. Copy the corresponding mpv and FFmpeg header files into `deps/include/`, replacing the current ones. You can find them on GitHub [(e.g. mpv)](https://github.com/mpv-player/mpv/tree/master/libmpv), but it's recommended to copy them from the Homebrew or MacPorts installation. Always make sure the header files have the same version of the dylibs.

3. Run `other/parse_doc.rb`. This script will fetch the latest mpv documentation and generate `MPVOption.swift`, `MPVCommand.swift` and `MPVProperty.swift`. Copy them from `other/` to `iina/`, replacing the current files. This is only needed when updating libmpv. Note that if the API changes, the player source code may also need to be changed.

4. Run `other/change_lib_dependencies.rb`. This script will deploy the dependent libraries into `deps/lib`. If you're using a package manager to manage dependencies, invoke it like so:

	#### With Homebrew

	```console
	other/change_lib_dependencies.rb "$(brew --prefix)" "$(brew --prefix mpv-iina)/lib/libmpv.dylib"
	```

	#### With MacPorts

	```console
	port contents mpv | grep '\.dylib$' | xargs other/change_lib_dependencies.rb /opt/local
	```

5. Open `iina.xcodeproj` in the [latest public version of Xcode](https://apps.apple.com/app/xcode/id497799835). *IINA may not build if you use any other version.*

6. Remove all references to `.dylib` files from the Frameworks group in the sidebar and add all the `.dylib` files in `deps/lib` to that group by clicking  "Add Files to iina..." in the context menu.

7. Add all the imported `.dylib` files into the "Copy Dylibs" phase under "Build Phases" tab of the iina target.

8. Make sure the necessary `.dylib` files are present in the "Link Binary With Libraries" phase under "Build Phases". Xcode should have already added all dylibs under this section.

9. Build the project.

## Contributing

IINA is always looking for contributions, whether it's through bug reports, code, or new translations.

* If you find a bug in IINA, or would like to suggest a new feature or enhancement, it'd be nice if you could [search your problem first](https://github.com/iina/iina/issues); while we don't mind duplicates, keeping issues unique helps us save time and consolidates effort. If you can't find your issue, feel free to [file a new one](https://github.com/iina/iina/issues/new/choose).

* If you're looking to contribute code, please read [CONTRIBUTING.md](CONTRIBUTING.md) — it has information on IINA's process for handling contributions, and tips on how the code is structured to make your work easier.

* If you'd like to translate IINA to your language, please visit [IINA's instance of Crowdin](https://translate.iina.io/). You can create an account for free and start translating. Please do not send a pull request to this repo directly, Crowdin will automatically sync new translations with our repo. If you want to translate IINA into a new language that is currently not on the list, feel free to open an issue.
