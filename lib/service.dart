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
}
