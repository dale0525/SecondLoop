#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<USAGE
Usage: $0 --app <path-to-app> --output <path-to-dmg> [--volume-name <name>]

Create a macOS DMG with a drag-to-Applications Finder layout.
USAGE
}

app_path=''
output_path=''
volume_name='SecondLoop'

while [[ $# -gt 0 ]]; do
  case "$1" in
    --app)
      app_path="${2:-}"
      shift 2
      ;;
    --output)
      output_path="${2:-}"
      shift 2
      ;;
    --volume-name)
      volume_name="${2:-}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [[ -z "${app_path}" || -z "${output_path}" ]]; then
  usage >&2
  exit 2
fi

if [[ ! -d "${app_path}" ]]; then
  echo "App bundle not found: ${app_path}" >&2
  exit 1
fi

app_basename="$(basename "${app_path}")"
tmp_root="$(mktemp -d)"
stage_dir="${tmp_root}/stage"
rw_dmg="${tmp_root}/staging.dmg"
attach_device=''
mount_point=''

cleanup() {
  if [[ -n "${attach_device}" ]]; then
    hdiutil detach "${attach_device}" -quiet >/dev/null 2>&1 || true
  elif [[ -n "${mount_point}" ]]; then
    hdiutil detach "${mount_point}" -quiet >/dev/null 2>&1 || true
  fi
  rm -rf "${tmp_root}"
}
trap cleanup EXIT

create_background_image() {
  local output_png="$1"
  swift - "${output_png}" <<'SWIFT'
import AppKit
import Foundation

let outputPath = CommandLine.arguments[1]
let size = NSSize(width: 660, height: 420)
let canvas = NSImage(size: size)
canvas.lockFocus()

let bounds = NSRect(origin: .zero, size: size)
let gradient = NSGradient(
  starting: NSColor(calibratedRed: 0.95, green: 0.97, blue: 1.00, alpha: 1.0),
  ending: NSColor(calibratedRed: 0.87, green: 0.92, blue: 1.00, alpha: 1.0)
)
gradient?.draw(in: bounds, angle: 90)

let headlineAttributes: [NSAttributedString.Key: Any] = [
  .font: NSFont.systemFont(ofSize: 32, weight: .semibold),
  .foregroundColor: NSColor(calibratedRed: 0.10, green: 0.15, blue: 0.28, alpha: 1.0)
]
("Drag SecondLoop to Applications" as NSString).draw(
  at: NSPoint(x: 64, y: 330),
  withAttributes: headlineAttributes
)

let subtitleAttributes: [NSAttributedString.Key: Any] = [
  .font: NSFont.systemFont(ofSize: 16, weight: .regular),
  .foregroundColor: NSColor(calibratedRed: 0.23, green: 0.30, blue: 0.46, alpha: 1.0)
]
("Drop the app icon onto Applications to install." as NSString).draw(
  at: NSPoint(x: 66, y: 294),
  withAttributes: subtitleAttributes
)

let arrowColor = NSColor(calibratedRed: 0.19, green: 0.33, blue: 0.89, alpha: 0.88)
arrowColor.setStroke()

let arrowBody = NSBezierPath()
arrowBody.lineWidth = 12
arrowBody.lineCapStyle = .round
arrowBody.move(to: NSPoint(x: 272, y: 198))
arrowBody.curve(
  to: NSPoint(x: 422, y: 198),
  controlPoint1: NSPoint(x: 320, y: 214),
  controlPoint2: NSPoint(x: 374, y: 214)
)
arrowBody.stroke()

let arrowHead = NSBezierPath()
arrowHead.lineWidth = 12
arrowHead.lineCapStyle = .round
arrowHead.move(to: NSPoint(x: 402, y: 224))
arrowHead.line(to: NSPoint(x: 434, y: 198))
arrowHead.line(to: NSPoint(x: 402, y: 172))
arrowHead.stroke()

canvas.unlockFocus()

guard
  let tiffData = canvas.tiffRepresentation,
  let bitmap = NSBitmapImageRep(data: tiffData),
  let pngData = bitmap.representation(using: .png, properties: [:])
else {
  fputs("Failed to build DMG background image\n", stderr)
  exit(1)
}

do {
  try pngData.write(to: URL(fileURLWithPath: outputPath))
} catch {
  fputs("Failed to write DMG background image: \(error)\n", stderr)
  exit(1)
}
SWIFT
}

mkdir -p "${stage_dir}/.background"
cp -R "${app_path}" "${stage_dir}/"
ln -s "/Applications" "${stage_dir}/Applications"
create_background_image "${stage_dir}/.background/dmg-background.png"

hdiutil create \
  -volname "${volume_name}" \
  -srcfolder "${stage_dir}" \
  -ov \
  -format UDRW \
  "${rw_dmg}" >/dev/null

attach_output="$(hdiutil attach -readwrite -noverify -noautoopen "${rw_dmg}")"
attach_device="$(awk '/^\/dev\// {print $1; exit}' <<<"${attach_output}")"
mount_point="$(awk '/\/Volumes\// {print $NF; exit}' <<<"${attach_output}")"

if [[ -z "${attach_device}" || -z "${mount_point}" ]]; then
  echo "Failed to mount DMG for layout configuration" >&2
  exit 1
fi

mounted_volume_name="$(basename "${mount_point}")"
osascript - "${mounted_volume_name}" "${app_basename}" <<'APPLESCRIPT'
on run argv
  set volume_name to item 1 of argv
  set app_name to item 2 of argv

  tell application "Finder"
    tell disk volume_name
      open
      set container_window to container window
      set current view of container_window to icon view
      set toolbar visible of container_window to false
      set statusbar visible of container_window to false
      set bounds of container_window to {120, 120, 780, 540}

      set opts to icon view options of container_window
      set arrangement of opts to not arranged
      set icon size of opts to 120
      set text size of opts to 14
      set background picture of opts to file ".background:dmg-background.png"

      set position of item app_name of container_window to {170, 210}
      set position of item "Applications" of container_window to {500, 210}

      update without registering applications
      delay 1
      close
      open
      update without registering applications
      delay 1
    end tell
  end tell
end run
APPLESCRIPT

sync
hdiutil detach "${attach_device}" -quiet >/dev/null
attach_device=''

mkdir -p "$(dirname "${output_path}")"
rm -f "${output_path}"
hdiutil convert \
  "${rw_dmg}" \
  -format UDZO \
  -imagekey zlib-level=9 \
  -o "${output_path}" >/dev/null

echo "Created DMG: ${output_path}"
