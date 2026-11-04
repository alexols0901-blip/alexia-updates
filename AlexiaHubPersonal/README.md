# Alexia HUB Personal 1.1.2

Requires macOS 13+ and Apple command-line tools. The script library is saved locally in ~/Library/Application Support/AlexiaHubPersonal/scripts.json.

Existing users: open Updates, Save and check, then Install 1.1.2 and Install and restart. You can also choose this ZIP directly in Updates. The updater compiles on your Mac without Terminal interaction.

First installation: unzip, open Terminal, type bash followed by a space, drag Build.command into Terminal, and press Return. The app opens when compilation succeeds. Move dist/Alexia HUB Personal.app into Applications.

## Changes

Apps contains ChatGPT (opens https://chatgpt.com/ in your default browser), Discord, Roblox, and MacSploit. Native apps launch their installed .app bundles. If an app cannot be located, select its bundle once. Its location is remembered. Installed app icons appear beside each launcher, with a system symbol fallback. The file-executable RobloxPlayer shortcut has been removed.

The app now includes a generated cyan code icon in the sidebar and its macOS bundle. The online update source is configured in Updates. Existing feed configuration and scripts are preserved. Sidebar rows remain full-width buttons.

## Image

App icon created with the built-in image-generation tool. Prompt: polished square macOS icon for Alexia HUB Personal, dark charcoal rounded square, luminous cyan <_> code symbol, simple silhouette, subtle blue depth, no words. The generated icon is converted into a multiresolution ICNS asset in Assets/AppIcon.icns.

## Validation

ZIP integrity, icon decoding, source references, and build shell syntax checked. This Linux workspace cannot compile or launch macOS SwiftUI code. Compilation, native app launches, update replacement and icon refresh need verification on your Mac.
