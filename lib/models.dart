enum RecordingState { idle, recording, paused, error }

enum VehicleStatus { online, offline, unknown }

VehicleStatus toStatus(String name) {
  final i = VehicleStatus.values.indexWhere((e) => e.name == name);
  if (i == -1) return VehicleStatus.unknown;
  return VehicleStatus.values[i];
}

///* LocationSnapshotModel
///
/// This model represents one paired (LatLng + image) entry under a vehicle.
class LocationSnapshotModel {
  final String databaseId;
  final double latitude;
  final double longitude;
  final String imageUrl;
  final DateTime timestamp;

  LocationSnapshotModel({
    required this.databaseId,
    required this.latitude,
    required this.longitude,
    required this.imageUrl,
    required this.timestamp,
  });

  static LocationSnapshotModel fromDB(String id, Map<String, dynamic> data) {
    return LocationSnapshotModel(
      databaseId: id,
      latitude: double.tryParse(data['lat']?.toString() ?? '') ?? -1,
      longitude: double.tryParse(data['lng']?.toString() ?? '') ?? -1,
      imageUrl: data['imageUrl'] as String,
      timestamp: DateTime.fromMillisecondsSinceEpoch(
        int.tryParse(data['timestamp']?.toString() ?? '') ?? -1,
      ),
    );
  }
}

///* VehicleModel
///
/// This model represents Represents a full vehicle node, including
/// its live location and the complete list of historical snapshots.
class VehicleModel {
  final String vehicleId;
  final VehicleStatus status;
  final DateTime lastSeen;
  final double currentLatitude;
  final double currentLongitude;
  final List<LocationSnapshotModel> snapshots;

  VehicleModel({
    required this.vehicleId,
    required this.status,
    required this.lastSeen,
    required this.currentLatitude,
    required this.currentLongitude,
    required this.snapshots,
  });

  /// Whether the vehicle has reported activity recently (within [threshold]).
  bool isActiveWithin(Duration threshold) => DateTime.now().difference(lastSeen) <= threshold;

  /// The most recent snapshot, or null if none exist yet.
  LocationSnapshotModel? get latestSnapshot => snapshots.isNotEmpty ? snapshots.last : null;

  static VehicleModel fromDB(String id, Map<String, dynamic> data) {
    final rawLocation = data['location'] as Map<dynamic, dynamic>? ?? {};
    final lat = double.tryParse(rawLocation['lat']?.toString() ?? '') ?? -1;
    final lng = double.tryParse(rawLocation['lng']?.toString() ?? '') ?? -1;

    final rawSnapshots = data['snapshots'] as Map<dynamic, dynamic>? ?? {};
    final snapshots =
        rawSnapshots.entries
            .map((e) => LocationSnapshotModel.fromDB(e.key, Map<String, dynamic>.from(e.value)))
            .toList()
          ..sort((a, b) => a.timestamp.compareTo(b.timestamp));

    return VehicleModel(
      vehicleId: id,
      status: toStatus(data['status']),
      lastSeen: DateTime.fromMillisecondsSinceEpoch(
        int.tryParse(data['lastSeen']?.toString() ?? '') ?? -1,
      ),
      currentLatitude: lat,
      currentLongitude: lng,
      snapshots: snapshots,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is VehicleModel &&
      other.vehicleId == vehicleId &&
      other.status == status &&
      other.lastSeen == lastSeen &&
      other.currentLatitude == currentLatitude &&
      other.currentLongitude == currentLongitude &&
      other.snapshots.length == snapshots.length;

  @override
  int get hashCode =>
      Object.hash(vehicleId, status, lastSeen, currentLatitude, currentLongitude, snapshots.length);
}

class VideoModel {
  final String databaseId;
  final String url;
  final String filename;
  final DateTime timestamp;

  VideoModel({
    required this.databaseId,
    required this.url,
    required this.filename,
    required this.timestamp,
  });

  static VideoModel fromDB(String id, Map<String, dynamic> data) {
    return VideoModel(
      databaseId: id,
      url: data['url'] as String? ?? '',
      filename: data['filename'] as String? ?? '',
      timestamp: DateTime.fromMillisecondsSinceEpoch(
        int.tryParse(data['timestamp']?.toString() ?? '') ?? -1,
      ),
    );
  }
}
