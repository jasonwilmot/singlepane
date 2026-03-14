# 009: Image Viewer Enhancements (Zoom, EXIF, Rotate)

**Priority:** P2
**Effort:** Medium
**Labels:** Feature, Preview
**Phase:** 2 — Differentiator

## Problem

Current image preview loads images in a WKWebView via base64 data URI. There's no zoom, no rotation, no metadata display. For a file manager that aims to outshine Finder, the image viewer needs to be a proper tool, not just a thumbnail display.

## Requirements

### Zoom
- Pinch-to-zoom on trackpad
- Scroll wheel zoom (with modifier key, e.g., Cmd+scroll)
- Zoom in/out buttons or Cmd+Plus / Cmd+Minus
- Fit-to-window (default) and actual-size toggle
- Zoom level indicator (e.g., "150%")
- Double-click to toggle between fit-to-window and actual size

### Pan
- Click-drag to pan when zoomed in
- Two-finger scroll to pan

### Rotation
- Rotate 90° CW/CCW buttons or keyboard shortcuts
- Rotation is non-destructive (display only, does not modify file)

### EXIF / Metadata
- Toggleable info overlay or sidebar showing:
  - Dimensions (width × height px)
  - File size
  - Color space
  - DPI
  - EXIF data (camera, lens, aperture, shutter speed, ISO, date taken, GPS)
- Keyboard shortcut to toggle info (e.g., Cmd+I)

### Format Support
- All formats currently supported: PNG, JPG, GIF, WebP, SVG, BMP, TIFF, HEIC
- Animated GIF/WebP should animate

## Implementation Notes

- Replace WKWebView image display with native `NSImageView` or custom `NSView` with Core Graphics rendering
- Use `CGImageSource` for metadata extraction (`CGImageSourceCopyPropertiesAtIndex`)
- EXIF data lives in `kCGImagePropertyExifDictionary`
- GPS data in `kCGImagePropertyGPSDictionary`
- For zoom: use `NSScrollView` with a scalable content view, or `CALayer` transforms
- For animated GIF: `NSImage` with `animates = true` or `CGImageSource` frame iteration

## Files to Create

- `totalcommander/UI/Preview/ImageViewerViewController.swift`

## Files to Modify

- `totalcommander/UI/Preview/PreviewContainerViewController.swift` — route images to new viewer instead of WKWebView
- `totalcommander/UI/Preview/MarkdownPreviewViewController.swift` — remove image handling (delegate to new viewer)

## Acceptance Criteria

- [ ] Pinch-to-zoom works smoothly
- [ ] Cmd+Plus/Minus zoom works
- [ ] Double-click toggles fit/actual size
- [ ] Pan works when zoomed in
- [ ] Rotate buttons work (non-destructive)
- [ ] EXIF metadata displayed for JPG/HEIC photos
- [ ] Dimensions and file size always shown
- [ ] Animated GIFs animate
- [ ] 50MP image loads without lag
- [ ] Theme-aware background (dark background behind image)
