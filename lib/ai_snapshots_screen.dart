import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import 'models.dart';
import 'theme.dart';

class SnapshotsScreen extends StatefulWidget {
  final VehicleModel vehicle;

  const SnapshotsScreen({super.key, required this.vehicle});

  @override
  State<SnapshotsScreen> createState() => _SnapshotsScreenState();
}

class _SnapshotsScreenState extends State<SnapshotsScreen> {
  late LocationSnapshotModel _selected;
  late final MapController _mapCtrl;

  // Reverse so newest is at the top of the list
  late final List<LocationSnapshotModel> _snapshots;

  bool panelOpen = true;

  @override
  void initState() {
    super.initState();
    _mapCtrl = MapController();
    _snapshots = widget.vehicle.snapshots.reversed.toList();
    if (_snapshots.isEmpty) {
      // Shouldn't reach here if the button guard is in place,
      // but this prevents a crash if the screen is ever opened directly.
      WidgetsBinding.instance.addPostFrameCallback((_) => Navigator.of(context).pop());
      return;
    }
    _selected = _snapshots.first;
  }

  @override
  void dispose() {
    _mapCtrl.dispose();
    super.dispose();
  }

  void _pick(LocationSnapshotModel snap) {
    setState(() => _selected = snap);
    _mapCtrl.move(LatLng(snap.latitude, snap.longitude), 15);
  }

  // ─────────────────────────────────────────────────────────────
  // Build
  // ─────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bg,
      body: Column(
        children: [
          _TopBar(vehicle: widget.vehicle, selected: _selected),
          Expanded(
            child: Row(
              children: [
                // ── Collapsible snapshot list ──────────────────
                AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  curve: Curves.easeInOut,
                  width: panelOpen ? 260 : 0,
                  // ClipRect prevents the list content from
                  // bleeding out while the width animates to 0.
                  child: ClipRect(
                    child: OverflowBox(
                      alignment: Alignment.topLeft,
                      minWidth: 260,
                      maxWidth: 260,
                      child: _SnapshotList(
                        snapshots: _snapshots,
                        selected: _selected,
                        onPick: _pick,
                      ),
                    ),
                  ),
                ),

                // ── Detail view + toggle tab ────────────────────
                Expanded(
                  child: Stack(
                    children: [
                      _SnapshotDetail(snap: _selected, mapCtrl: _mapCtrl),

                      // Toggle tab — always visible on the left edge
                      Positioned(
                        left: 0,
                        top: 0,
                        bottom: 0,
                        child: GestureDetector(
                          onTap: () => setState(() => panelOpen = !panelOpen),
                          child: MouseRegion(
                            cursor: SystemMouseCursors.click,
                            child: Container(
                              width: 20,
                              decoration: BoxDecoration(
                                color: AppTheme.surface,
                                border: const Border(
                                  right: BorderSide(color: AppTheme.panelBorder),
                                ),
                              ),
                              child: Center(
                                child: AnimatedRotation(
                                  turns: panelOpen ? 0 : 0.5,
                                  duration: const Duration(milliseconds: 250),
                                  curve: Curves.easeInOut,
                                  child: const Icon(
                                    Icons.chevron_left,
                                    color: AppTheme.textSecondary,
                                    size: 16,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Top bar
// ─────────────────────────────────────────────────────────────

class _TopBar extends StatelessWidget {
  final VehicleModel vehicle;
  final LocationSnapshotModel selected;

  const _TopBar({required this.vehicle, required this.selected});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: const BoxDecoration(
        color: AppTheme.surface,
        border: Border(bottom: BorderSide(color: AppTheme.panelBorder)),
      ),
      child: Row(
        children: [
          // Back button
          GestureDetector(
            onTap: Navigator.of(context).pop,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: AppTheme.panel,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: AppTheme.panelBorder),
              ),
              child: const Row(
                children: [
                  Icon(Icons.arrow_back_ios, color: AppTheme.textSecondary, size: 12),
                  SizedBox(width: 4),
                  Text(
                    'BACK',
                    style: TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.5,
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(width: 16),

          // Vehicle ID
          Container(
            width: 4,
            height: 20,
            decoration: BoxDecoration(
              color: AppTheme.amber,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 10),
          Text(
            vehicle.vehicleId,
            style: const TextStyle(
              color: AppTheme.textPrimary,

              fontSize: 14,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.5,
            ),
          ),

          const SizedBox(width: 8),

          Text(
            '/ SNAPSHOTS',
            style: TextStyle(
              color: AppTheme.textSecondary.withValues(alpha: 0.6),
              fontSize: 11,
              letterSpacing: 1.5,
            ),
          ),

          const Spacer(),

          // Selected snapshot timestamp
          Text(
            AppConsts.fullFormat.format(selected.timestamp),
            style: const TextStyle(
              color: AppTheme.amber,

              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Snapshot list (left panel)
// ─────────────────────────────────────────────────────────────

class _SnapshotList extends StatelessWidget {
  final List<LocationSnapshotModel> snapshots;
  final LocationSnapshotModel selected;
  final ValueChanged<LocationSnapshotModel> onPick;

  const _SnapshotList({required this.snapshots, required this.selected, required this.onPick});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 260,
      decoration: const BoxDecoration(
        color: AppTheme.surface,
        border: Border(right: BorderSide(color: AppTheme.panelBorder)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // List header
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
            child: Row(
              children: [
                const Text(
                  'ALL SNAPSHOTS',
                  style: TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 2,
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppTheme.amber.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: AppTheme.amber.withValues(alpha: 0.3)),
                  ),
                  child: Text(
                    '${snapshots.length}',
                    style: const TextStyle(
                      color: AppTheme.amber,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),

          const Divider(height: 1, color: AppTheme.panelBorder),

          // Items
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
              itemCount: snapshots.length,
              itemBuilder: (context, i) => _SnapshotTile(
                snap: snapshots[i],
                index: snapshots.length - i, // newest = highest number
                isSelected: selected.databaseId == snapshots[i].databaseId,
                onTap: () => onPick(snapshots[i]),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Snapshot Tile
// ─────────────────────────────────────────────────────────────

class _SnapshotTile extends StatelessWidget {
  final LocationSnapshotModel snap;
  final int index;
  final bool isSelected;
  final VoidCallback onTap;

  const _SnapshotTile({
    required this.snap,
    required this.index,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 130),
        margin: const EdgeInsets.only(bottom: 6),
        decoration: BoxDecoration(
          color: isSelected ? AppTheme.panel : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? AppTheme.amber.withValues(alpha: 0.5) : AppTheme.panelBorder,
          ),
        ),
        child: Row(
          children: [
            // Thumbnail
            ClipRRect(
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(7),
                bottomLeft: Radius.circular(7),
              ),
              child: Image.network(
                snap.imageUrl,
                width: 64,
                height: 64,
                fit: BoxFit.cover,
                loadingBuilder: (_, child, progress) => progress == null
                    ? child
                    : Container(
                        width: 64,
                        height: 64,
                        color: AppTheme.bg,
                        child: const Center(
                          child: SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 1.5,
                              color: AppTheme.amber,
                            ),
                          ),
                        ),
                      ),
                errorBuilder: (_, _, _) => Container(
                  width: 64,
                  height: 64,
                  color: AppTheme.bg,
                  child: const Icon(Icons.broken_image, color: AppTheme.textSecondary, size: 20),
                ),
              ),
            ),

            // Meta
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Snap index badge
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                          decoration: BoxDecoration(
                            color: isSelected ? AppTheme.amber.withValues(alpha: 0.2) : AppTheme.bg,
                            borderRadius: BorderRadius.circular(3),
                          ),
                          child: Text(
                            '#$index',
                            style: TextStyle(
                              color: isSelected ? AppTheme.amber : AppTheme.textSecondary,
                              fontSize: 9,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 5),

                    Text(
                      AppConsts.shortDateFormat.format(snap.timestamp),
                      style: const TextStyle(
                        color: AppTheme.textPrimary,
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                      ),
                    ),

                    const SizedBox(height: 2),

                    Text(
                      AppConsts.timeFormat.format(snap.timestamp),
                      style: const TextStyle(
                        color: AppTheme.textSecondary,

                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            if (isSelected)
              const Padding(
                padding: EdgeInsets.only(right: 8),
                child: Icon(Icons.chevron_right, color: AppTheme.amber, size: 16),
              ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Snapshot Detail (right panel)
// ─────────────────────────────────────────────────────────────

class _SnapshotDetail extends StatelessWidget {
  final LocationSnapshotModel snap;
  final MapController mapCtrl;

  const _SnapshotDetail({required this.snap, required this.mapCtrl});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        // ── Top half — Map ───────────────────────────────────
        Expanded(
          child: Stack(
            children: [
              FlutterMap(
                mapController: mapCtrl,
                options: MapOptions(
                  initialCenter: LatLng(snap.latitude, snap.longitude),
                  initialZoom: 15,
                ),
                children: [
                  TileLayer(
                    urlTemplate: AppConsts.mapTileUrl,
                    subdomains: const ['a', 'b', 'c'],
                    userAgentPackageName: 'com.fleet.web',
                    tileProvider: NetworkTileProvider(),
                  ),
                  MarkerLayer(
                    markers: [
                      Marker(
                        point: LatLng(snap.latitude, snap.longitude),
                        width: 48,
                        height: 48,
                        child: const _SnapMarker(),
                      ),
                    ],
                  ),
                ],
              ),

              // Zoom controls
              Positioned(
                right: 12,
                bottom: 12,
                child: Material(
                  color: AppTheme.panel,
                  elevation: 4,
                  borderRadius: BorderRadius.circular(10),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        color: AppTheme.textSecondary,
                        icon: const Icon(Icons.add),
                        onPressed: () {
                          final cam = mapCtrl.camera;
                          mapCtrl.move(cam.center, cam.zoom + 1);
                        },
                      ),
                      const Divider(height: 1, color: AppTheme.panelBorder),
                      IconButton(
                        color: AppTheme.textSecondary,
                        icon: const Icon(Icons.remove),
                        onPressed: () {
                          final cam = mapCtrl.camera;
                          mapCtrl.move(cam.center, cam.zoom - 1);
                        },
                      ),
                    ],
                  ),
                ),
              ),

              // Coordinates pill
              Positioned(
                left: 12,
                bottom: 12,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppTheme.panel.withValues(alpha: 0.9),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: AppTheme.panelBorder),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.my_location, color: AppTheme.amber, size: 12),
                      const SizedBox(width: 6),
                      Text(
                        '${snap.latitude.toStringAsFixed(6)},  '
                        '${snap.longitude.toStringAsFixed(6)}',
                        style: const TextStyle(
                          color: AppTheme.textPrimary,

                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),

        // Divider
        const VerticalDivider(width: 1, color: AppTheme.panelBorder),

        // ── Bottom half — Image ──────────────────────────────
        Expanded(
          child: GestureDetector(
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
            child: Stack(
              fit: StackFit.expand,
              children: [
                // Image fills the half
                Image.network(
                  snap.imageUrl,
                  fit: BoxFit.cover,
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
                  errorBuilder: (_, e, _) => Container(
                    color: AppTheme.surface,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.broken_image, color: AppTheme.textSecondary, size: 36),
                        const SizedBox(height: 8),
                        Text(
                          e.toString(),
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: AppTheme.textSecondary, fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                ),

                // Gradient overlay at the bottom with timestamp
                Positioned(
                  left: 15,
                  right: 0,
                  bottom: 0,
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(16, 32, 16, 16),
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                        colors: [Colors.black87, Colors.transparent],
                      ),
                    ),
                    child: Text(
                      AppConsts.fullFormat.format(snap.timestamp),
                      style: const TextStyle(
                        color: Colors.white,

                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ].reversed.toList(),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Snap pin marker
// ─────────────────────────────────────────────────────────────

class _SnapMarker extends StatelessWidget {
  const _SnapMarker();

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 14,
          height: 14,
          decoration: BoxDecoration(
            color: AppTheme.amber,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 2),
            boxShadow: [
              BoxShadow(
                color: AppTheme.amber.withValues(alpha: 0.6),
                blurRadius: 10,
                spreadRadius: 2,
              ),
            ],
          ),
        ),
        const SizedBox(height: 2),
        Container(
          width: 2,
          height: 12,
          decoration: BoxDecoration(color: AppTheme.amber, borderRadius: BorderRadius.circular(1)),
        ),
      ],
    );
  }
}
