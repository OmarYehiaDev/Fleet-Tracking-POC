import 'package:fleet_tracking_poc/models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import 'ai_snapshots_screen.dart';
import 'app_version.dart';
import 'service.dart';
import 'theme.dart';

class WebScreen extends StatefulWidget {
  const WebScreen({super.key});

  @override
  State<WebScreen> createState() => _WebScreenState();
}

class _WebScreenState extends State<WebScreen> {
  // The service vehicleId is irrelevant on the web side —
  // we only use the streaming methods which accept forVehicleId.
  final _service = FleetManagementService.instance;
  final _mapCtrl = MapController();

  VehicleModel? _selected;

  @override
  void dispose() {
    _mapCtrl.dispose();
    super.dispose();
  }

  void _selectVehicle(VehicleModel vehicle) {
    setState(() => _selected = vehicle);
    if (vehicle.currentLatitude != -1 && vehicle.currentLongitude != -1) {
      _mapCtrl.move(LatLng(vehicle.currentLatitude, vehicle.currentLongitude), 14.0);
    }
  }

  // ─────────────────────────────────────────────────────────────
  // Build
  // ─────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bg,
      body: StreamBuilder<List<VehicleModel>>(
        stream: _service.streamAllVehicles(),
        builder: (context, snapshot) {
          final vehicles = snapshot.data ?? [];

          // Keep _selected in sync with latest data
          if (_selected != null) {
            final updated = vehicles.where((v) => v.vehicleId == _selected!.vehicleId).firstOrNull;
            if (updated != null && updated != _selected) {
              WidgetsBinding.instance.addPostFrameCallback(
                (_) => setState(() => _selected = updated),
              );
            }
          }

          return Row(
            children: [
              // ── Left sidebar ─────────────────────────────────
              _Sidebar(
                vehicles: vehicles,
                selected: _selected,
                onSelect: _selectVehicle,
                onDeselect: () => setState(() => _selected = null),
              ),

              // ── Map ──────────────────────────────────────────
              Expanded(
                child: _FleetMap(
                  vehicles: vehicles,
                  selected: _selected,
                  mapCtrl: _mapCtrl,
                  onMarkerTap: _selectVehicle,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Sidebar
// ─────────────────────────────────────────────────────────────

class _Sidebar extends StatelessWidget {
  final List<VehicleModel> vehicles;
  final VehicleModel? selected;
  final ValueChanged<VehicleModel> onSelect;
  final VoidCallback onDeselect;

  const _Sidebar({
    required this.vehicles,
    required this.selected,
    required this.onSelect,
    required this.onDeselect,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 300,
      decoration: const BoxDecoration(
        color: AppTheme.surface,
        border: Border(right: BorderSide(color: AppTheme.panelBorder)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Container(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: AppTheme.panelBorder)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.max,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      width: 4,
                      height: 20,
                      decoration: BoxDecoration(
                        color: AppTheme.amber,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(width: 10),
                    const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'FLEET MONITOR',
                          style: TextStyle(
                            color: AppTheme.textPrimary,
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 2.5,
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'Live · Real-time',
                          style: TextStyle(
                            color: AppTheme.textSecondary,
                            fontSize: 10,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                Text(
                  'v${AppVersion.label}',
                  style: const TextStyle(
                    fontSize: 10,
                    letterSpacing: 1.5,
                    color: AppTheme.textSecondary,
                  ),
                ),
              ],
            ),
          ),

          // Vehicle count
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
            child: Text(
              '${vehicles.length} VEHICLE${vehicles.length == 1 ? '' : 'S'}',
              style: const TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 2,
              ),
            ),
          ),

          // Vehicle list
          Expanded(
            child: vehicles.isEmpty
                ? const Center(
                    child: Text(
                      'No vehicles online',
                      style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                    itemCount: vehicles.length,
                    itemBuilder: (context, i) => _VehicleCard(
                      vehicle: vehicles[i],
                      isSelected: selected?.vehicleId == vehicles[i].vehicleId,
                      onTap: () => onSelect(vehicles[i]),
                    ),
                  ),
          ),

          // Selected vehicle detail panel
          if (selected != null) _DetailPanel(vehicle: selected!, onClose: onDeselect),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Vehicle Card
// ─────────────────────────────────────────────────────────────

class _VehicleCard extends StatelessWidget {
  final VehicleModel vehicle;
  final bool isSelected;
  final VoidCallback onTap;

  const _VehicleCard({required this.vehicle, required this.isSelected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    // final isActive = vehicle.isActiveWithin(const Duration(minutes: 5));
    final statusColor = vehicle.status.name == 'online' ? AppTheme.green : AppTheme.red;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isSelected ? AppTheme.panel : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? AppTheme.amber.withValues(alpha: 0.5) : AppTheme.panelBorder,
          ),
        ),
        child: Row(
          children: [
            // Status dot
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: statusColor,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: statusColor.withValues(alpha: 0.5),
                    blurRadius: 6,
                    spreadRadius: 1,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),

            // Vehicle info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    vehicle.vehicleId,
                    style: const TextStyle(
                      color: AppTheme.textPrimary,

                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    vehicle.lastSeen.millisecondsSinceEpoch == -1
                        ? 'Never seen'
                        : 'Last: ${AppConsts.timestampFormat.format(vehicle.lastSeen)}',
                    style: const TextStyle(color: AppTheme.textSecondary, fontSize: 10),
                  ),
                ],
              ),
            ),

            // Snapshot count badge
            if (vehicle.snapshots.isNotEmpty)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: AppTheme.amber.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: AppTheme.amber.withValues(alpha: 0.3)),
                ),
                child: Text(
                  '${vehicle.snapshots.length}',
                  style: const TextStyle(
                    color: AppTheme.amber,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),

            const SizedBox(width: 8),
            const Icon(Icons.chevron_right, color: AppTheme.textSecondary, size: 16),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Detail Panel (selected vehicle)
// ─────────────────────────────────────────────────────────────

class _DetailPanel extends StatelessWidget {
  final VehicleModel vehicle;
  final VoidCallback onClose;

  const _DetailPanel({required this.vehicle, required this.onClose});

  @override
  Widget build(BuildContext context) {
    final snap = vehicle.latestSnapshot;
    final hasLocation = vehicle.currentLatitude != -1 && vehicle.currentLongitude != -1;

    return Container(
      decoration: const BoxDecoration(
        color: AppTheme.panel,
        border: Border(top: BorderSide(color: AppTheme.panelBorder)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Panel header
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 12, 10),
            child: Row(
              children: [
                const Text(
                  'VEHICLE DETAIL',
                  style: TextStyle(
                    color: AppTheme.amber,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 2,
                  ),
                ),
                const Spacer(),
                GestureDetector(
                  onTap: onClose,
                  child: const Icon(Icons.close, color: AppTheme.textSecondary, size: 16),
                ),
              ],
            ),
          ),

          // Latest image
          if (snap != null)
            GestureDetector(
              onTap: () {
                showDialog(
                  context: context,
                  builder: (cxt) {
                    return Card(
                      margin: EdgeInsets.symmetric(
                        vertical: MediaQuery.of(context).size.height * 0.1,
                        horizontal: MediaQuery.of(context).size.width * 0.1,
                      ),
                      color: AppTheme.panel,
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          spacing: 16,
                          children: [
                            Row(
                              mainAxisSize: MainAxisSize.max,
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  AppConsts.fullFormat.format(snap.timestamp),
                                  style: TextStyle(
                                    fontSize: 16,
                                    color: AppTheme.amber,

                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                IconButton(
                                  color: Colors.red,
                                  icon: Icon(Icons.close),
                                  onPressed: Navigator.of(cxt).pop,
                                ),
                              ],
                            ),
                            Expanded(
                              child: Image.network(
                                snap.imageUrl,
                                fit: BoxFit.contain,
                                loadingBuilder: (_, child, progress) => progress == null
                                    ? child
                                    : Container(
                                        color: AppTheme.surface,
                                        child: const Center(
                                          child: CircularProgressIndicator(
                                            strokeWidth: 1.5,
                                            color: AppTheme.amber,
                                          ),
                                        ),
                                      ),
                                errorBuilder: (_, e, st) => Container(
                                  color: AppTheme.surface,
                                  child: Center(
                                    child: Column(
                                      children: [
                                        Icon(Icons.broken_image, color: AppTheme.textSecondary),
                                        Text(
                                          e.toString(),
                                          style: TextStyle(
                                            color: AppTheme.textSecondary,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        Text(
                                          st?.toString() ?? "N/A",
                                          style: TextStyle(
                                            color: AppTheme.textSecondary,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: Image.network(
                    snap.imageUrl,
                    height: 140,
                    width: double.infinity,
                    fit: BoxFit.cover,
                    loadingBuilder: (_, child, progress) => progress == null
                        ? child
                        : Container(
                            height: 140,
                            color: AppTheme.surface,
                            child: const Center(
                              child: CircularProgressIndicator(
                                strokeWidth: 1.5,
                                color: AppTheme.amber,
                              ),
                            ),
                          ),
                    errorBuilder: (_, e, st) => Container(
                      height: 140,
                      color: AppTheme.surface,
                      child: Center(
                        child: Column(
                          children: [
                            Icon(Icons.broken_image, color: AppTheme.textSecondary),
                            Text(
                              e.toString(),
                              style: TextStyle(
                                color: AppTheme.textSecondary,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              st?.toString() ?? "N/A",
                              style: TextStyle(
                                color: AppTheme.textSecondary,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),

          // Metadata rows
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
            child: Column(
              children: [
                _MetaRow(
                  icon: Icons.circle,
                  iconColor: vehicle.status.name == 'online'
                      ? AppTheme.green
                      : AppTheme.textSecondary,
                  label: 'STATUS',
                  value: vehicle.status.name.toUpperCase(),
                ),
                const SizedBox(height: 8),
                _MetaRow(
                  icon: Icons.access_time,
                  iconColor: AppTheme.textSecondary,
                  label: 'LAST SEEN',
                  value: vehicle.lastSeen.millisecondsSinceEpoch == -1
                      ? '—'
                      : AppConsts.timestampFormat.format(vehicle.lastSeen),
                ),
                const SizedBox(height: 8),
                if (hasLocation)
                  _MetaRow(
                    icon: Icons.my_location,
                    iconColor: AppTheme.textSecondary,
                    label: 'LOCATION',
                    value:
                        '${vehicle.currentLatitude.toStringAsFixed(5)},\n'
                        '${vehicle.currentLongitude.toStringAsFixed(5)}',
                  ),
                const SizedBox(height: 8),
                _MetaRow(
                  icon: Icons.photo_library_outlined,
                  iconColor: AppTheme.textSecondary,
                  label: 'SNAPSHOTS',
                  value: '${vehicle.snapshots.length} captured',
                ),
                if (snap != null) ...[
                  const SizedBox(height: 8),
                  _MetaRow(
                    icon: Icons.schedule,
                    iconColor: AppTheme.textSecondary,
                    label: 'LAST SNAP',
                    value: AppConsts.timestampFormat.format(snap.timestamp),
                  ),
                ],
              ],
            ),
          ),

          // Snapshots Button
          SizedBox(
            width: double.infinity,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.amber,
                  foregroundColor: AppTheme.panel,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadiusGeometry.circular(15)),
                ),
                onPressed: vehicle.snapshots.isEmpty
                    ? null
                    : () {
                        Navigator.of(context).push(
                          MaterialPageRoute(builder: (_) => SnapshotsScreen(vehicle: vehicle)),
                        );
                      },
                child: Text(
                  "View all snapshots".toUpperCase(),
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MetaRow extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String label;
  final String value;

  const _MetaRow({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: iconColor, size: 12),
        const SizedBox(width: 8),
        Text(
          label,
          style: const TextStyle(
            color: AppTheme.textSecondary,
            fontSize: 9,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.5,
          ),
        ),
        const Spacer(),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: const TextStyle(
              color: AppTheme.textPrimary,
              fontSize: 11,

              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Fleet Map
// ─────────────────────────────────────────────────────────────

class _FleetMap extends StatelessWidget {
  final List<VehicleModel> vehicles;
  final VehicleModel? selected;
  final MapController mapCtrl;
  final ValueChanged<VehicleModel> onMarkerTap;

  const _FleetMap({
    required this.vehicles,
    required this.selected,
    required this.mapCtrl,
    required this.onMarkerTap,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        FlutterMap(
          mapController: mapCtrl,
          options: const MapOptions(initialCenter: LatLng(30.0444, 31.2357), initialZoom: 5),
          children: [
            // Dark base tiles
            TileLayer(
              urlTemplate: AppConsts.mapTileUrl,
              subdomains: const ['a', 'b', 'c'],
              userAgentPackageName: 'com.fleet.web',
              tileProvider: NetworkTileProvider(),
            ),

            // Vehicle markers
            MarkerLayer(
              markers: vehicles
                  .where((v) => v.currentLatitude != -1 && v.currentLongitude != -1)
                  .map(
                    (v) => Marker(
                      point: LatLng(v.currentLatitude, v.currentLongitude),
                      width: 60,
                      height: 60,
                      child: GestureDetector(
                        onTap: () => onMarkerTap(v),
                        child: _WebVehicleMarker(
                          vehicle: v,
                          isSelected: selected?.vehicleId == v.vehicleId,
                        ),
                      ),
                    ),
                  )
                  .toList(),
            ),
          ],
        ),
        Positioned(
          right: 12,
          bottom: 12,
          child: Material(
            color: AppTheme.panel,
            elevation: 4,
            borderRadius: BorderRadius.circular(12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  color: AppTheme.textSecondary,
                  icon: const Icon(Icons.add),
                  onPressed: () {
                    final camera = mapCtrl.camera;
                    mapCtrl.move(camera.center, camera.zoom + 1);
                  },
                ),
                const Divider(height: 1),
                IconButton(
                  color: AppTheme.textSecondary,
                  icon: const Icon(Icons.remove),
                  onPressed: () {
                    final camera = mapCtrl.camera;
                    mapCtrl.move(camera.center, camera.zoom - 1);
                  },
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Web Vehicle Marker
// ─────────────────────────────────────────────────────────────

class _WebVehicleMarker extends StatelessWidget {
  final VehicleModel vehicle;
  final bool isSelected;

  const _WebVehicleMarker({required this.vehicle, required this.isSelected});

  @override
  Widget build(BuildContext context) {
    final isActive = vehicle.status.name == 'online';
    final color = isSelected ? AppTheme.amber : (isActive ? AppTheme.green : AppTheme.red);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Label
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(4),
            boxShadow: [
              BoxShadow(color: color.withValues(alpha: 0.4), blurRadius: 8, spreadRadius: 1),
            ],
          ),
          child: Text(
            vehicle.vehicleId,
            style: TextStyle(
              color: isSelected ? AppTheme.bg : Colors.white,
              fontSize: 9,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        const SizedBox(height: 2),
        // Pin icon
        Icon(
          isSelected ? Icons.location_pin : Icons.circle,
          color: color,
          size: isSelected ? 24 : 14,
        ),
      ],
    );
  }
}
