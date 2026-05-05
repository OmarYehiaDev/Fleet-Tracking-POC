<div align="center">

# 🚛 Fleet Tracking POC

A real-time fleet management proof-of-concept built with **Flutter** — one codebase, two clients: a **mobile driver app** and a **web command-center dashboard**, both powered by Firebase.

[![Flutter](https://img.shields.io/badge/Flutter-3.x-02569B?logo=flutter&logoColor=white)](https://flutter.dev)
[![Firebase](https://img.shields.io/badge/Firebase-Realtime_DB_+_Storage-FFCA28?logo=firebase&logoColor=black)](https://firebase.google.com)
[![Platform](https://img.shields.io/badge/Platform-Android_%7C_iOS_%7C_Web-4CAF50)](#)

</div>

---

## 📖 Overview

Fleet Tracking POC solves a simple problem: **how do you know where your vehicles are and what they're seeing — in real time?**

- The **mobile app** runs on each driver's device. It streams GPS coordinates continuously and automatically captures a photo every 15 seconds, pairing it with the current location and pushing both to Firebase atomically.
- The **web dashboard** gives admins and board members a live birds-eye view of every active vehicle, their last-known location, latest image, and full snapshot history — all updating without a single page refresh.

---

## 📱 Mobile Client

### Login & Go Online

| Enter Vehicle Name | Go Online |
|:---:|:---:|
| ![](https://raw.githubusercontent.com/OmarYehiaDev/Fleet-Tracking-POC/main/screenshots/mobile-01.jpg) | ![](https://raw.githubusercontent.com/OmarYehiaDev/Fleet-Tracking-POC/main/screenshots/mobile-02.jpg) |
| Enter a vehicle name/ID to register and begin transmitting | Vehicle goes online — GPS stream starts and presence is registered in RTDB |

### Live Map

| Live Position | Location Pinned |
|:---:|:---:|
| ![](https://raw.githubusercontent.com/OmarYehiaDev/Fleet-Tracking-POC/main/screenshots/mobile-03.jpg) | ![](https://raw.githubusercontent.com/OmarYehiaDev/Fleet-Tracking-POC/main/screenshots/mobile-04.jpg) |
| Current position tracked live on a dark tile map | Vehicle marker with name label pinned at exact coordinates |

### Recording Mode

| Start Recording | REC Badge — Counting Down |
|:---:|:---:|
| ![](https://raw.githubusercontent.com/OmarYehiaDev/Fleet-Tracking-POC/main/screenshots/mobile-05.jpg) | ![](https://raw.githubusercontent.com/OmarYehiaDev/Fleet-Tracking-POC/main/screenshots/mobile-06.jpg) |
| Tap START RECORDING to begin automatic capture every 15 seconds | Pulsing red REC badge shows countdown to next capture |

| Snapshot Captured | Uploading | Subsequent Captures |
|:---:|:---:|:---:|
| ![](https://raw.githubusercontent.com/OmarYehiaDev/Fleet-Tracking-POC/main/screenshots/mobile-07.jpg) | ![](https://raw.githubusercontent.com/OmarYehiaDev/Fleet-Tracking-POC/main/screenshots/mobile-08.jpg) | ![](https://raw.githubusercontent.com/OmarYehiaDev/Fleet-Tracking-POC/main/screenshots/mobile-09.jpg) |
| Camera fires headlessly — no preview interrupts the driver | Image uploads to Firebase Storage, URL written to RTDB | Subsequent captures continue every 15 seconds automatically |

### Going Offline

| Stop Recording | Go Offline |
|:---:|:---:|
| ![](https://raw.githubusercontent.com/OmarYehiaDev/Fleet-Tracking-POC/main/screenshots/mobile-10.jpg) | ![](https://raw.githubusercontent.com/OmarYehiaDev/Fleet-Tracking-POC/main/screenshots/mobile-11.jpg) |
| Stop recording returns to online-only mode, streams kept alive | Go offline cancels all streams and marks vehicle offline in RTDB |

---

## 🖥️ Web Client

### Fleet Overview

| Live Fleet Map | Vehicle Selected |
|:---:|:---:|
| ![](https://raw.githubusercontent.com/OmarYehiaDev/Fleet-Tracking-POC/main/screenshots/web-01.jpeg) | ![](https://raw.githubusercontent.com/OmarYehiaDev/Fleet-Tracking-POC/main/screenshots/web-02.jpeg) |
| All vehicles rendered as live markers — green for online, red for offline | Clicking a vehicle card or marker flies the map to it and opens the detail panel |

### Vehicle Detail Panel

| Latest Image + Metadata | Image Lightbox |
|:---:|:---:|
| ![](https://raw.githubusercontent.com/OmarYehiaDev/Fleet-Tracking-POC/main/screenshots/web-03.jpeg) | ![](https://raw.githubusercontent.com/OmarYehiaDev/Fleet-Tracking-POC/main/screenshots/web-04.jpeg) |
| Detail panel shows latest snapshot, status, last-seen timestamp, coordinates, and snapshot count | Tap the thumbnail to open the full-resolution image in a dialog with timestamp header |

### Snapshot History

| All Snapshots | Collapsed Sidebar |
|:---:|:---:|
| ![](https://raw.githubusercontent.com/OmarYehiaDev/Fleet-Tracking-POC/main/screenshots/web-05.jpeg) | ![](https://raw.githubusercontent.com/OmarYehiaDev/Fleet-Tracking-POC/main/screenshots/web-06.jpeg) |
| Master-detail viewer — list on the left, map + image on the right, synced to every selection | Panel slides away with animated chevron toggle for a full-screen map view |

---

## ✨ Features

### 📱 Mobile

- **Vehicle registration** — enter a name/ID to go online and begin transmitting to RTDB
- **Live GPS stream** — continuous position updates via `geolocator`, fires every 10 meters moved
- **Real-time map** — current position pinned on a dark Stadia Maps tile layer via `flutter_map`
- **Recording mode** — headless rear camera captures a photo + location pair every **15 seconds** automatically
- **Countdown display** — pulsing `REC · next in Xs` badge counts down to the next capture
- **Presence system** — `onDisconnect()` hook marks the vehicle offline the moment connection drops
- **Manual go offline** — gracefully cancels all streams, updates RTDB status, returns to login

### 🖥️ Web

- **Live fleet map** — all vehicles as labeled markers, positions update in real-time from RTDB
- **Sidebar vehicle list** — streams every vehicle with glowing status dot, last-seen timestamp, and snapshot count badge
- **Vehicle detail panel** — latest image (tap to enlarge), status, coordinates, and snapshot history button
- **Map fly-to** — clicking any vehicle card or marker smoothly flies the map to that location
- **Snapshot history screen** — full master-detail viewer: scrollable list on the left, map + image on the right
- **Collapsible list panel** — slides in/out with a 250ms animated chevron toggle
- **Per-snapshot detail** — each snapshot shows its pinned location on the map and the captured image with a timestamp overlay
- **Image lightbox** — tap any thumbnail to open full-resolution image in a dialog with timestamp header
- **Custom zoom controls** — `+` / `−` buttons overlaid on every map surface

---

## 🏗️ Architecture

```
┌──────────────────────────────────────────────────────────────┐
│                        Flutter App                           │
│                                                              │
│   kIsWeb ──┬──► WebScreen       (admin dashboard)           │
│            └──► MobileScreen    (driver app)                 │
└─────────────────────────┬────────────────────────────────────┘
                          │
              FleetManagementService
                          │
         ┌────────────────┼─────────────────┐
         ▼                ▼                 ▼
 Firebase RTDB     Firebase Storage     Geolocator
 location +        raw image files      GPS stream
 metadata + URLs   (CORS configured)
```

### Data flow

```
Mobile device
  │
  ├─ Geolocator stream ──────────────────► RTDB: .../location & lastSeen
  │
  └─ Camera (every 15s)
       │
       ├─ putFile() ──────────────────────► Firebase Storage
       │                ◄── download URL ──┘
       └─ push({ lat, lng, imageUrl }) ──► RTDB: .../snapshots/{id}
                                                        │
Web dashboard ◄──── StreamBuilder listens ─────────────┘
```

---

## 🗂️ RTDB Structure

```
fleet/
  vehicles/
    {vehicleId}/
      status:   "active" | "offline"
      lastSeen: 1713600000000
      location/
        lat: 30.04440
        lng: 31.23570
      snapshots/
        {pushId}/
          lat:       30.04440
          lng:       31.23570
          imageUrl:  "https://firebasestorage.googleapis.com/..."
          timestamp: 1713600000000
```

---

## 📦 Data Models

| Model | Responsibility |
|---|---|
| `LocationSnapshotModel` | One paired (LatLng + image URL + timestamp) entry, parsed via `fromDB()` |
| `VehicleModel` | Full vehicle node — status, lastSeen, current location, sorted snapshot list. Exposes `latestSnapshot` getter and `isActiveWithin(Duration)` helper |

---

## 📁 Project Structure

```
lib/
├── main.dart                       # Firebase init, AppVersion init, runApp
├── home_view.dart                  # kIsWeb router — pure switch, no Scaffold
├── models.dart                     # LocationSnapshotModel, VehicleModel
├── service.dart                    # FleetManagementService (RTDB + Storage)
├── app_version.dart                # package_info_plus version label helper
├── mobile_screen.dart              # idle → online → recording state machine
├── web_screen.dart                 # Sidebar + live fleet map
├── snapshots_screen.dart           # Full snapshot history master-detail viewer
├── mobile/
│   └── mobile_home_widget.dart     # Delegates to MobileScreen
└── web/
    └── web_home_widget.dart        # Delegates to WebScreen
```

---

## 🔧 Tech Stack

| Layer | Technology |
|---|---|
| Framework | Flutter 3.x |
| Realtime sync | Firebase Realtime Database |
| File storage | Firebase Storage |
| Web hosting | Firebase Hosting |
| Maps | `flutter_map` + Stadia Maps dark tiles |
| Location | `geolocator` |
| Camera | `camera` |
| Date formatting | `intl` |
| Version info | `package_info_plus` |

---

## 🚀 Getting Started

### Prerequisites

- Flutter 3.x
- Firebase project with Realtime Database and Storage enabled
- Stadia Maps API key — free tier at [stadiamaps.com](https://stadiamaps.com)

### 1. Clone

```bash
git clone https://github.com/OmarYehiaDev/Fleet-Tracking-POC.git
cd Fleet-Tracking-POC
```

### 2. Install dependencies

```bash
flutter pub get
```

### 3. Firebase setup

```bash
dart pub global activate flutterfire_cli
flutterfire configure
```

### 4. CORS for Firebase Storage (required for web)

Create `cors.json` at the project root:

```json
[
  {
    "origin": ["https://your-project-id.web.app"],
    "method": ["GET"],
    "maxAgeSeconds": 3600
  }
]
```

```bash
gsutil cors set cors.json gs://your-project-id.firebasestorage.app
```

### 5. Run

```bash
# Mobile
flutter run

# Web
flutter run -d chrome
```

---

## 🌐 Deploy to Firebase Hosting

```bash
flutter build web --release
firebase deploy --only hosting
```

---

## 🔐 RTDB Security Rules

```json
{
  "rules": {
    "fleet": {
      "vehicles": {
        "$vehicleId": {
          ".write": "auth != null && auth.uid === $vehicleId",
          ".read": "auth != null"
        }
      }
    }
  }
}
```

---

## Killing the DVR service

```powershell
adb shell appops set com.zqc.camera android:camera deny | adb shell am force-stop com.zqc.camera | adb shell kill -9 1978 | adb reboot | adb wait-for-device
```

---

## Re-enabling it again

- You need to factory reset it or do the following cmd:

```powershell
adb shell pm enable com.zqc.camera
adb shell appops set com.zqc.camera android:camera allow
```

---

## Checking the status of cameras

```powershell
adb shell dumpsys media.camera > active_cams.txt | notepad active_cams.txt
```

---

## 📄 License

MIT — see [LICENSE](LICENSE) for details.
