# kashi GeoField Pro 🗺️

**Professional Android Field Mapping Application**

A powerful, offline-capable GIS field data collection app for surveyors, land records officers, and field engineers. Built with Flutter.

---

## Features

### 🗺️ Map Engine
- Interactive map with OpenStreetMap tiles (via `flutter_map`)
- Draw **polygons**, **paths/lines**, and **markers** by tapping on map
- Edit, move, and delete drawn shapes
- **Area calculation** in hectares & acres
- **Perimeter** in meters & kilometers
- Undo/redo drawing actions
- Snap to GPS location
- Search villages/towns by name (Nominatim API)

### 📥 Village Map Import
- Import boundary maps from **KML**, **KMZ**, and **GeoJSON** formats
- Display village boundaries as overlays on the map
- Area auto-calculation on import
- Export village boundaries as KML or PDF

### 📂 KML File Manager
- Import and manage multiple KML/KMZ layer files
- Toggle layer visibility on/off
- Custom layer colors with color picker
- Export KML as KMZ compressed archive
- Share files via system share sheet

### 🌐 Offline Maps
- Tile caching as you browse (automatic)
- Save region bounding boxes for offline reference
- Manage and delete cached regions
- Storage usage estimation

### 🖨️ PDF Reports
- Generate professional PDF maps for polygons and village boundaries
- Include area, perimeter, coordinates data
- Print history tracking
- Share/export via system share sheet

### ⚙️ Settings
- Organization name and logo configuration
- Default polygon color picker
- Default map zoom level
- Page size and orientation for PDF exports
- Data management (export all, clear all, print history)

---

## Tech Stack

| Component | Package |
|---|---|
| Map | `flutter_map` ^6.x + OpenStreetMap |
| Database | `sqflite` |
| File Import | `file_picker` ^8.x |
| KML/KMZ Parsing | `xml` + `archive` |
| GeoJSON | custom parser |
| PDF Generation | `pdf` + `printing` |
| Location | `geolocator` |
| Color Picker | `flutter_colorpicker` |
| Sharing | `share_plus` |
| Settings | `shared_preferences` |

---

## Getting Started

### Prerequisites
- Flutter SDK ≥ 3.0.0
- Android SDK (minSdk 23 / Android 6.0+)
- Java 11+

### Build & Run

```bash
# Clone the repository
git clone https://github.com/kashinathyankanchi-maker/kashi-geofield-pro.git
cd kashi-geofield-pro

# Install dependencies
flutter pub get

# Run on connected Android device
flutter run

# Build release APK
flutter build apk --release
```

### APK Location
After build: `build/app/outputs/flutter-apk/app-release.apk`

---

## Project Structure

```
lib/
├── core/
│   ├── database/      # SQLite helpers
│   ├── models/        # Data models
│   └── utils/         # GeoCalculator, KmlEngine, PdfGenerator
├── features/
│   ├── map/           # Map screen, controller, widgets
│   ├── villages/      # Village import & detail screens
│   ├── kml/           # KML file management screens
│   ├── offline_maps/  # Offline tile management
│   └── settings/      # App settings screen
└── shared/
    ├── theme.dart     # App theme (dark mode, green accent)
    └── bottom_nav.dart # Main scaffold with bottom nav
```

---

## Permissions Required (Android)

- `ACCESS_FINE_LOCATION` — GPS snap-to-location
- `ACCESS_COARSE_LOCATION` — Fallback location
- `READ_EXTERNAL_STORAGE` — Import KML/GeoJSON files
- `WRITE_EXTERNAL_STORAGE` — Export PDF/KML files
- `INTERNET` — Map tiles download

---

## License

Copyright © 2024 KashiGeo Technologies. All rights reserved.
