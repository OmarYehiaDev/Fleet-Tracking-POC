import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import 'app_version.dart';
import 'service.dart';
import 'theme.dart';

// ─────────────────────────────────────────────────────────────
// State machine
// ─────────────────────────────────────────────────────────────
enum _DriveState { idle, online, recording }

class MobileScreen extends StatefulWidget {
  const MobileScreen({super.key});

  @override
  State<MobileScreen> createState() => _MobileScreenState();
}

class _MobileScreenState extends State<MobileScreen> with TickerProviderStateMixin {
  // ── controllers ──────────────────────────────────────────────
  final _nameCtrl = TextEditingController();
  final _mapCtrl = MapController();

  // ── state ────────────────────────────────────────────────────
  _DriveState _driveState = _DriveState.idle;
  String? _errorMsg;
  bool _isBusy = false; // loading spinner during async ops

  // ── service & streams ────────────────────────────────────────
  FleetManagementService? _service;
  StreamSubscription<Position>? _locationSub;
  Position? _position;

  // ── camera ───────────────────────────────────────────────────
  CameraController? _cameraCtrl;

  // ── recording timers ─────────────────────────────────────────
  Timer? _captureTimer; // fires every 15 s → capture + push
  Timer? _countdownTimer; // fires every 1 s  → decrement display
  int _countdown = 15;

  // ── pulse animation for REC badge ────────────────────────────
  late final AnimationController _pulseCtrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);
  late final Animation<double> _pulseAnim = Tween(begin: 0.4, end: 1.0).animate(_pulseCtrl);

  // ─────────────────────────────────────────────────────────────
  // Lifecycle
  // ─────────────────────────────────────────────────────────────

  @override
  void dispose() {
    _nameCtrl.dispose();
    _mapCtrl.dispose();
    _pulseCtrl.dispose();
    _locationSub?.cancel();
    _captureTimer?.cancel();
    _countdownTimer?.cancel();
    _cameraCtrl?.dispose();
    super.dispose();
  }

  // ─────────────────────────────────────────────────────────────
  // Actions
  // ─────────────────────────────────────────────────────────────

  Future<void> _goOnline() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      setState(() => _errorMsg = 'Enter a vehicle name first.');
      return;
    }

    setState(() {
      _isBusy = true;
      _errorMsg = null;
    });

    // 1. Request location permission
    final hasPermission = await _requestLocationPermission();
    if (!hasPermission) {
      setState(() {
        _isBusy = false;
        _errorMsg = 'Location permission is required.';
      });
      return;
    }

    // 2. Get initial position
    final position = await Geolocator.getCurrentPosition();

    // 3. Register service & presence
    _service = FleetManagementService.instance;
    await _service!.registerPresence(name);

    // 4. Start location stream
    // _locationSub = _service!.startLocationStream(name);

    // Override listener to also update local map
    // _locationSub?.cancel();
    _locationSub =
        Geolocator.getPositionStream(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
            distanceFilter: 10,
          ),
        ).listen((pos) {
          setState(() => _position = pos);
          _mapCtrl.move(LatLng(pos.latitude, pos.longitude), 15.0);
          // Write to RTDB directly — no startLocationStream() here
          _service!.updateVehicleStatus(name, pos.latitude, pos.longitude);
        });

    setState(() {
      _position = position;
      _driveState = _DriveState.online;
      _isBusy = false;
    });

    // Center map on initial position
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _mapCtrl.move(LatLng(position.latitude, position.longitude), 15.0);
    });
  }

  Future<void> _startRecording() async {
    setState(() {
      _isBusy = true;
      _errorMsg = null;
    });

    // Init camera (back-facing, headless — no preview needed)
    try {
      final cameras = await availableCameras();
      final back = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );
      _cameraCtrl = CameraController(back, ResolutionPreset.medium, enableAudio: false);
      await _cameraCtrl!.initialize();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Camera unavailable: $e')));
      }
      setState(() {
        _isBusy = false;
        _errorMsg = 'Camera unavailable: $e';
      });
      return;
    }

    // Capture immediately, then every 15 s
    await _captureAndPush(_nameCtrl.text);
    _countdown = 15;
    _captureTimer = Timer.periodic(const Duration(seconds: 15), (_) async {
      await _captureAndPush(_nameCtrl.text);
      setState(() => _countdown = 15);
    });

    // 1-second display countdown
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _countdown = (_countdown - 1).clamp(0, 15));
    });

    setState(() {
      _driveState = _DriveState.recording;
      _isBusy = false;
    });
  }

  Future<void> _captureAndPush(String name) async {
    if (_position == null || _cameraCtrl == null) return;
    try {
      final xFile = await _cameraCtrl!.takePicture();
      await _service!.pushSnapshot(
        name,
        File(xFile.path),
        _position!.latitude,
        _position!.longitude,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Camera unavailable: $e')));
      }
      debugPrint('Snapshot error: $e');
    }
  }

  void _stopRecording() {
    _captureTimer?.cancel();
    _countdownTimer?.cancel();
    _cameraCtrl?.dispose();
    _cameraCtrl = null;
    setState(() {
      _driveState = _DriveState.online;
      _countdown = 15;
    });
  }

  Future<void> _goOffline() async {
    _stopRecording();
    _locationSub?.cancel();
    await _service?.goOffline(_nameCtrl.text);
    setState(() {
      _driveState = _DriveState.idle;
      _position = null;
      _service = null;
    });
  }

  Future<bool> _requestLocationPermission() async {
    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    return perm == LocationPermission.always || perm == LocationPermission.whileInUse;
  }

  // ─────────────────────────────────────────────────────────────
  // Build
  // ─────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bg,
      body: switch (_driveState) {
        _DriveState.idle => _buildIdleScreen(),
        _DriveState.online || _DriveState.recording => _buildMapScreen(),
      },
    );
  }

  // ── IDLE SCREEN ──────────────────────────────────────────────

  Widget _buildIdleScreen() {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 64),

            // Logo / header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      width: 8,
                      height: 32,
                      decoration: BoxDecoration(
                        color: AppTheme.amber,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Text(
                      'FLEET\nTRACKER',
                      style: TextStyle(
                        color: AppTheme.textPrimary,
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        height: 1.1,
                        letterSpacing: 3,
                      ),
                    ),
                  ],
                ),
                Text(
                  'v${AppVersion.label}',
                  style: const TextStyle(
                    fontSize: 14,
                    letterSpacing: 1.5,
                    color: AppTheme.textSecondary,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 16),
            const Text(
              'Enter your vehicle ID to begin\ntransmitting your location.',
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 13, height: 1.6),
            ),

            const Spacer(),

            // Label
            const Text(
              'VEHICLE NAME',
              style: TextStyle(
                color: AppTheme.amber,
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 2,
              ),
            ),
            const SizedBox(height: 8),

            // Text field
            TextField(
              controller: _nameCtrl,
              style: const TextStyle(
                color: AppTheme.textPrimary,

                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
              decoration: InputDecoration(
                hintText: 'e.g. TRUCK-01',
                hintStyle: TextStyle(
                  color: AppTheme.textSecondary.withValues(alpha: 0.5),

                  fontSize: 18,
                ),
                filled: true,
                fillColor: AppTheme.panel,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: AppTheme.amber, width: 1.5),
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
              ),
              textCapitalization: TextCapitalization.characters,
            ),

            // Error message
            if (_errorMsg != null) ...[
              const SizedBox(height: 10),
              Text(_errorMsg!, style: const TextStyle(color: AppTheme.red, fontSize: 12)),
            ],

            const SizedBox(height: 20),

            // Go Online button
            SizedBox(
              width: double.infinity,
              height: 54,
              child: ElevatedButton(
                onPressed: _isBusy ? null : _goOnline,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.amber,
                  foregroundColor: AppTheme.bg,
                  disabledBackgroundColor: AppTheme.amber.withValues(alpha: 0.4),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  elevation: 0,
                ),
                child: _isBusy
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.bg),
                      )
                    : const Text(
                        'GO ONLINE',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 2.5,
                        ),
                      ),
              ),
            ),

            const SizedBox(height: 48),
          ],
        ),
      ),
    );
  }

  // ── MAP SCREEN (online + recording) ──────────────────────────

  Widget _buildMapScreen() {
    final isRecording = _driveState == _DriveState.recording;
    final pos = _position;

    return Stack(
      children: [
        // ── Full-screen map ──────────────────────────────────
        FlutterMap(
          mapController: _mapCtrl,
          options: MapOptions(
            initialCenter: pos != null
                ? LatLng(pos.latitude, pos.longitude)
                : const LatLng(30.0444, 31.2357),
            initialZoom: 15,
          ),
          children: [
            TileLayer(
              urlTemplate: AppConsts.mapTileUrl,
              subdomains: const ['a', 'b', 'c'],
              userAgentPackageName: 'com.fleet.tracker',
              tileProvider: NetworkTileProvider(),
            ),
            if (pos != null)
              MarkerLayer(
                markers: [
                  Marker(
                    point: LatLng(pos.latitude, pos.longitude),
                    width: 56,
                    height: 56,
                    child: _VehicleMarker(label: _nameCtrl.text, isRecording: isRecording),
                  ),
                ],
              ),
          ],
        ),

        // ── Top bar ──────────────────────────────────────────
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                // Vehicle name chip
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppTheme.bg.withValues(alpha: 0.85),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: AppTheme.amber.withValues(alpha: 0.4)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: isRecording ? AppTheme.red : AppTheme.green,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _nameCtrl.text,
                        style: const TextStyle(
                          color: AppTheme.textPrimary,

                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),

                const Spacer(),

                // Go offline button
                GestureDetector(
                  onTap: _goOffline,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppTheme.bg.withValues(alpha: 0.85),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: AppTheme.red.withValues(alpha: 0.5)),
                    ),
                    child: const Text(
                      'GO OFFLINE',
                      style: TextStyle(
                        color: AppTheme.red,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.5,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),

        // ── REC badge (recording only) ────────────────────────
        if (isRecording)
          SafeArea(
            child: Align(
              alignment: Alignment.topCenter,
              child: Padding(
                padding: const EdgeInsets.only(top: 16),
                child: FadeTransition(
                  opacity: _pulseAnim,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppTheme.red,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.fiber_manual_record, color: Colors.white, size: 10),
                        const SizedBox(width: 6),
                        Text(
                          'REC  ·  next in ${_countdown}s',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),

        // ── Bottom control bar ────────────────────────────────
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: Container(
            padding: EdgeInsets.fromLTRB(20, 16, 20, MediaQuery.of(context).padding.bottom + 16),
            decoration: BoxDecoration(
              color: AppTheme.panel.withValues(alpha: 0.95),
              border: Border(top: BorderSide(color: Colors.white.withValues(alpha: 0.06))),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Coordinates readout
                if (_position != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 14),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.my_location, color: AppTheme.amber, size: 13),
                        const SizedBox(width: 6),
                        Text(
                          '${_position!.latitude.toStringAsFixed(5)}, '
                          '${_position!.longitude.toStringAsFixed(5)}',
                          style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                        ),
                      ],
                    ),
                  ),

                // Record / Stop button
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    onPressed: _isBusy ? null : (isRecording ? _stopRecording : _startRecording),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: isRecording ? AppTheme.red : AppTheme.amber,
                      foregroundColor: isRecording ? Colors.white : AppTheme.bg,
                      disabledBackgroundColor: (isRecording ? AppTheme.red : AppTheme.amber)
                          .withValues(alpha: 0.4),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      elevation: 0,
                    ),
                    child: _isBusy
                        ? SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: isRecording ? Colors.white : AppTheme.bg,
                            ),
                          )
                        : Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                isRecording ? Icons.stop_rounded : Icons.fiber_manual_record,
                                size: 18,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                isRecording ? 'STOP RECORDING' : 'START RECORDING',
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 2,
                                ),
                              ),
                            ],
                          ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 16.0),
                  child: Text(
                    'v${AppVersion.label}',
                    style: const TextStyle(
                      fontSize: 12,
                      letterSpacing: 1.5,
                      color: AppTheme.textSecondary,
                    ),
                  ),
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
// Vehicle Marker Widget
// ─────────────────────────────────────────────────────────────

class _VehicleMarker extends StatelessWidget {
  final String label;
  final bool isRecording;

  const _VehicleMarker({required this.label, required this.isRecording});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          decoration: BoxDecoration(
            color: isRecording ? AppTheme.red : AppTheme.amber,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: isRecording ? Colors.white : AppTheme.bg,
              fontSize: 9,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        const SizedBox(height: 2),
        Icon(Icons.location_pin, color: isRecording ? AppTheme.red : AppTheme.amber, size: 28),
      ],
    );
  }
}
