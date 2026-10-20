#!/bin/zsh
# Development build only. The finished app does not need this toolchain or this script.
set -euo pipefail
cd "${0:A:h}"

action="${1:-build}"
if [[ "$action" != build && "$action" != test ]]; then
  print -u2 'Aufruf: ./build.sh [build|test]'
  exit 2
fi

# Reuse this workspace's already resolved packages when present; use a project-local
# cache when the project is copied elsewhere. Xcode's checked-in lockfile still pins versions.
package_cache="$PWD/../../work/MLXSourcePackages"
if [[ ! -d "$package_cache/checkouts/mlx-swift" ]]; then
  package_cache="$PWD/.build/SourcePackages"
fi

toolchain_args=()
if ! /usr/bin/xcrun metal --version >/dev/null 2>&1; then
  # Xcode 27 on this Mac shipped a Metal stub and its component catalog failed.
  # The unchanged, checksum-verified Apple compiler is registered in this standard folder.
  for candidate in "$HOME"/Library/Developer/Toolchains/Metal*.xctoolchain(N); do
    if "$candidate/usr/bin/metal" --version >/dev/null 2>&1; then
      identifier=$(/usr/libexec/PlistBuddy -c 'Print :Identifier' "$candidate/ToolchainInfo.plist")
      toolchain_args=(-toolchain "$identifier")
      break
    fi
  done
  if (( ${#toolchain_args} == 0 )); then
    print -u2 'Metal-Compiler fehlt. In Xcode unter Settings → Components installieren oder xcodebuild -downloadComponent MetalToolchain verwenden.'
    exit 1
  fi
fi

/usr/bin/xcodebuild -project LokalKIWorkspace.xcodeproj \
  -scheme LokalKIWorkspace -configuration Debug \
  -destination 'platform=macOS,arch=arm64' \
  -clonedSourcePackagesDirPath "$package_cache" \
  "${toolchain_args[@]}" -jobs 4 "$action"
