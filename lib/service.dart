import 'dart:async';
import 'dart:io';

import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:geolocator/geolocator.dart';
import 'package:fleet_tracking_poc/models.dart';

class FleetManagementService {
  FleetManagementService._();
  static final FleetManagementService instance = FleetManagementService._();

  final _storage = FirebaseStorage.instance;
  final _db = FirebaseDatabase.instance.ref();
  DatabaseReference get _vehiclesRef => _db.child('fleet/vehicles');

  // ───────────────────────────────────────────────────────────── //
  //                      TRACKING SECTION                         //
  // ───────────────────────────────────────────────────────────── //

  ///* REGISTER VEHICLE PRESENSE
  ///
  /// Call once on app init. Automatically marks the vehicle as
  /// 'offline' if the connection drops unexpectedly.
  Future<void> registerPresence(String vehicleId) async {
    await _vehiclesRef.child(vehicleId).update({'status': VehicleStatus.online.name});
    await _vehiclesRef.child(vehicleId).onDisconnect().update({
      'status': VehicleStatus.offline.name,
    });
  }

  ///* GO OFFLINE
  ///
  /// Manually marks the vehicle as offline (e.g. on user logout).
  Future<void> goOffline(String vehicleId) async {
    await _vehiclesRef.child(vehicleId).update({'status': VehicleStatus.offline.name});
  }

  ///* STREAM VEHICLE'S LOCATION
  ///
  /// Starts a continuous location stream, writes every position update to RTDB,
  /// and returns the [StreamSubscription] so the caller can cancel it on logout.
  StreamSubscription<Position> startLocationStream(String vehicleId) {
    return Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 5, // fires every 5 meters moved
      ),
    ).listen((position) {
      updateVehicleStatus(vehicleId, position.latitude, position.longitude);
    });
  }

  Future<void> updateVehicleStatus(String vehicleId, double lat, double lng) async {
    await _vehiclesRef.child(vehicleId).update({
      'location': {'lat': lat, 'lng': lng},
      'lastSeen': ServerValue.timestamp,
      'status': VehicleStatus.online.name,
    });
  }

  ///* SEND A NEW SNAPSHOT
  ///
  /// This function pushes the newly taken image with location to the RTDB
  Future<void> pushSnapshot(String vehicleId, File imageFile, double lat, double lng) async {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final storageRef = _storage.ref('fleet/$vehicleId/photos/$timestamp.jpg');
    final uploadTask = await storageRef.putFile(imageFile);
    final imageUrl = await uploadTask.ref.getDownloadURL();

    await _vehiclesRef.child('$vehicleId/snapshots').push().set({
      'lat': lat,
      'lng': lng,
      'imageUrl': imageUrl,
      'timestamp': ServerValue.timestamp,
    });
  }

  ///* SEND A DEVICE VIDEO
  ///
  /// Uploads a single video [file] to Firebase Storage under
  /// `device-videos/{vehicleId}/{filename}` and writes an entry
  /// under `fleet/vehicles/{vehicleId}/videos` in the Realtime
  /// Database with the download URL and server timestamp.
  ///
  /// Throws if the upload or database write fails so the caller
  /// can count successes/failures independently per file.
  Future<void> pushVideo(String vehicleId, File videoFile) async {
    final filename = videoFile.path.split('/').last;
    final storageRef = _storage.ref('device-videos/$vehicleId/$filename');

    // Upload the video file
    final uploadTask = await storageRef.putFile(
      videoFile,
      SettableMetadata(contentType: _contentTypeForFile(filename)),
    );
    final videoUrl = await uploadTask.ref.getDownloadURL();

    // Record the entry in RTDB under the vehicle node
    await _vehiclesRef.child('$vehicleId/videos').push().set({
      'url': videoUrl,
      'filename': filename,
      'timestamp': ServerValue.timestamp,
    });
  }

  /// Returns a best-guess MIME type for common video extensions.
  String _contentTypeForFile(String filename) {
    final ext = filename.split('.').last.toLowerCase();
    const types = {
      'mp4': 'video/mp4',
      'mov': 'video/quicktime',
      'avi': 'video/x-msvideo',
      'mkv': 'video/x-matroska',
      '3gp': 'video/3gpp',
      'webm': 'video/webm',
    };
    return types[ext] ?? 'video/mp4';
  }

  // ───────────────────────────────────────────────────────────── //
  //                      MONITORING SECTION                       //
  // ───────────────────────────────────────────────────────────── //

  ///* SHOW ALL VEHICLES
  ///
  /// Streams every vehicle node in real-time as a list of [VehicleModel].
  /// Used for the admin overview map.
  Stream<List<VehicleModel>> streamAllVehicles() {
    return _vehiclesRef.onValue.map((event) {
      final data = event.snapshot.value as Map<dynamic, dynamic>? ?? {};
      return data.entries
          .map((e) => VehicleModel.fromDB(e.key as String, Map<String, dynamic>.from(e.value)))
          .toList();
    });
  }

  ///* SHOW A SINGLE VEHICLE
  ///
  /// Streams a single vehicle node in real-time as a [VehicleModel].
  Stream<VehicleModel> streamVehicle(String targetVehicleId) {
    return _vehiclesRef.child(targetVehicleId).onValue.map((event) {
      return VehicleModel.fromDB(
        targetVehicleId,
        Map<String, dynamic>.from(event.snapshot.value as Map? ?? {}),
      );
    });
  }

  ///* SHOW SPECIFIC VEHICLE'S SNAPSHOTS
  ///
  /// This function gets the snapshots of the vehicle with the specified
  /// `vehicleId` from the RTDB. Also, sorted chronologically, optionally
  /// limit to [last] entries or fetch since [fromTimestamp] (Unix ms).
  Stream<List<LocationSnapshotModel>> streamVehicleSnapshots({
    required String vehicleId,
    int? fromTimestamp,
    int? last,
  }) {
    DatabaseReference ref = _vehiclesRef.child('$vehicleId/snapshots');
    Query query = ref.orderByChild('timestamp');
    if (fromTimestamp != null) query = query.startAt(fromTimestamp);
    if (last != null) query = query.limitToLast(last);

    return query.onValue.map((event) {
      final data = event.snapshot.value as Map<dynamic, dynamic>? ?? {};
      return _parseSnapshots(data);
    });
  }

  /// Converts a raw RTDB map into a sorted list of [LocationSnapshotModel].
  List<LocationSnapshotModel> _parseSnapshots(Map<dynamic, dynamic> data) {
    return data.entries
        .map(
          (e) => LocationSnapshotModel.fromDB(e.key as String, Map<String, dynamic>.from(e.value)),
        )
        .toList()
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
  }

  ///* SHOW SPECIFIC VEHICLE'S VIDEOS
  ///
  /// This function gets the videos of the vehicle with the specified
  /// `vehicleId` from the RTDB, sorted by newest first.
  Stream<List<VideoModel>> streamVehicleVideos(String vehicleId) {
    return _vehiclesRef.child('$vehicleId/videos').onValue.map((event) {
      final data = event.snapshot.value as Map<dynamic, dynamic>? ?? {};
      return data.entries
          .map((e) => VideoModel.fromDB(e.key as String, Map<String, dynamic>.from(e.value)))
          .toList()
        ..sort((a, b) => b.timestamp.compareTo(a.timestamp)); // newest first
    });
  }

  ///* DELETE A VEHICLE
  ///
  /// Deletes the vehicle with the specified `vehicleId` from the RTDB and all its snapshots.
  Future<void> deleteVehicle(String vehicleId) async {
    // Delete snapshots from Storage
    try {
      final photosRef = _storage.ref('fleet/$vehicleId/photos');
      final photoList = await photosRef.listAll();
      for (final item in photoList.items) {
        await item.delete();
      }
    } catch (_) {}

    // Delete videos from Storage
    try {
      final videosRef = _storage.ref('device-videos/$vehicleId');
      final videoList = await videosRef.listAll();
      for (final item in videoList.items) {
        await item.delete();
      }
    } catch (_) {}

    // Delete the entire vehicle node from RTDB (includes snapshots + videos metadata)
    await _vehiclesRef.child(vehicleId).remove();
  }
}
