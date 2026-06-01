import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:file_picker/file_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_version.dart';
import 'file_utils.dart';
import 'service.dart';
import 'theme.dart';

final _direction = CameraLensDirection.back;

// ─────────────────────────────────────────────────────────────
// State machine
// ─────────────────────────────────────────────────────────────
enum _DriveState { idle, online, recording }

// ─────────────────────────────────────────────────────────────
// SharedPreferences keys
// ─────────────────────────────────────────────────────────────
const _kVideoFolder = 'video_folder_path';
const _kVideoCount = 'video_send_count';

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

  // ── video upload state ───────────────────────────────────────
  bool _isUploadingVideos = false;
  int _videoUploadProgress = 0;
  int _videoUploadTotal = 0;

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

    // 4. Override listener to also update local map
    _locationSub =
        Geolocator.getPositionStream(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
            distanceFilter: 10,
          ),
        ).listen((pos) {
          setState(() => _position = pos);
          _mapCtrl.move(LatLng(pos.latitude, pos.longitude), 15.0);
          _service!.updateVehicleStatus(name, pos.latitude, pos.longitude);
        });

    setState(() {
      _position = position;
      _driveState = _DriveState.online;
      _isBusy = false;
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _mapCtrl.move(LatLng(position.latitude, position.longitude), 15.0);
    });
  }

  Future<void> _startRecording({bool skipCamera = false}) async {
    setState(() {
      _isBusy = true;
      _errorMsg = null;
    });

    if (!skipCamera) {
      try {
        final cameras = await availableCameras();
        debugPrint('Available cameras: ${cameras.map((c) => c.lensDirection).join(', ')}');
        final cam = cameras.firstWhere(
          (c) => c.lensDirection == _direction,
          orElse: () {
            final camList = cameras;
            debugPrint(
              'Available cameras (OrElse): ${camList.map((c) => c.lensDirection).join(', ')}',
            );
            camList.removeWhere((c) => c.lensDirection == _direction);
            if (camList.isEmpty) {
              throw 'No cameras found';
            } else {
              debugPrint('Back camera not found, using ${camList.first.lensDirection} instead');
              return camList.first;
            }
          },
        );
        _cameraCtrl = CameraController(cam, ResolutionPreset.low, enableAudio: false);
        await _cameraCtrl!.initialize();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Camera unavailable: $e')));
        }
        debugPrint('Camera unavailable: $e');
        setState(() {
          _isBusy = false;
          _errorMsg = 'Camera unavailable: $e';
        });
        return;
      }
    }

    await _captureAndPush(_nameCtrl.text, skipCamera: skipCamera);
    _countdown = 15;
    _captureTimer = Timer.periodic(const Duration(seconds: 15), (_) async {
      await _captureAndPush(_nameCtrl.text, skipCamera: skipCamera);
      setState(() => _countdown = 15);
    });

    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _countdown = (_countdown - 1).clamp(0, 15));
    });

    setState(() {
      _driveState = _DriveState.recording;
      _isBusy = false;
    });
  }

  Future<void> _captureAndPush(String name, {bool skipCamera = false}) async {
    if (_isBusy) return;
    if (skipCamera) {
      if (_position != null) {
        await _service!.updateVehicleStatus(name, _position!.latitude, _position!.longitude);
      }
      return;
    }
    if (!_cameraCtrl!.value.isInitialized) return;

    _isBusy = true;
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
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Snapshot error: $e')));
        await _reinitializeCamera();
      }
      debugPrint('Snapshot error: $e');
    } finally {
      _isBusy = false;
    }
  }

  Future<void> _reinitializeCamera() async {
    try {
      await _cameraCtrl!.dispose();
      await Future.delayed(const Duration(milliseconds: 500));
      final cameras = await availableCameras();
      final cam = cameras.firstWhere(
        (c) => c.lensDirection == _direction,
        orElse: () {
          final camList = cameras;
          debugPrint(
            'Available cameras (OrElse): ${camList.map((c) => c.lensDirection).join(', ')}',
          );
          camList.removeWhere((c) => c.lensDirection == _direction);
          if (camList.isEmpty) {
            throw 'No cameras found';
          } else {
            debugPrint('Back camera not found, using ${camList.first.lensDirection} instead');
            return camList.first;
          }
        },
      );
      _cameraCtrl = CameraController(cam, ResolutionPreset.low, enableAudio: false);
      await _cameraCtrl!.initialize();
      setState(() {});
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Re-init failed: $e')));
      }
      debugPrint('Re-init failed: $e');
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
  // Send Device Videos
  // ─────────────────────────────────────────────────────────────

  /// Loads saved folder/count prefs, shows dialog if missing, then uploads.
  Future<void> _onSendDeviceVideos() async {
    final prefs = await SharedPreferences.getInstance();
    String? folder = prefs.getString(_kVideoFolder);
    int? count = prefs.getInt(_kVideoCount);

    // Request storage permission first
    if (Platform.isAndroid) {
      final status = await Permission.manageExternalStorage.request();
      if (!status.isGranted) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Storage permission is required to read videos.')),
          );
        }
        return;
      }
    }

    // Always show dialog so user can change settings or re-pick folder.
    // Pre-populate with saved values if available.
    final result = await _showVideoSettingsDialog(initialFolder: folder, initialCount: count);
    if (result == null) return; // user cancelled

    folder = result.folder;
    count = result.count;

    if (result.remember) {
      await prefs.setString(_kVideoFolder, folder);
      await prefs.setInt(_kVideoCount, count);
    } else {
      // Clear any previously saved prefs if user unchecked "remember"
      await prefs.remove(_kVideoFolder);
      await prefs.remove(_kVideoCount);
    }

    await _uploadVideosFromFolder(folder, count);
  }

  /// Shows a dialog with a folder picker button and a count dropdown (1–15).
  /// Returns [_VideoSettings] on confirm, null on cancel.
  Future<_VideoSettings?> _showVideoSettingsDialog({String? initialFolder, int? initialCount}) {
    String? selectedFolder = initialFolder;
    int selectedCount = (initialCount ?? 5).clamp(1, 15);
    bool remember = true;

    return showDialog<_VideoSettings>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
              backgroundColor: AppTheme.panel,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              title: const Row(
                children: [
                  Icon(Icons.video_collection, color: AppTheme.amber, size: 20),
                  SizedBox(width: 10),
                  Text(
                    'VIDEO UPLOAD SETTINGS',
                    style: TextStyle(
                      color: AppTheme.textPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.5,
                    ),
                  ),
                ],
              ),
              content: SizedBox(
                width: MediaQuery.of(context).size.width * 0.6,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── Folder picker ────────────────────────
                    const Text(
                      'VIDEO FOLDER',
                      style: TextStyle(
                        color: AppTheme.amber,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.8,
                      ),
                    ),
                    const SizedBox(height: 6),
                    GestureDetector(
                      onTap: () async {
                        // FilePicker v11+ uses static methods (no .platform)
                        final picked = await FilePicker.getDirectoryPath(
                          dialogTitle: 'Select video folder',
                        );
                        if (picked != null) {
                          setDialogState(() => selectedFolder = picked);
                        }
                      },
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                        decoration: BoxDecoration(
                          color: AppTheme.bg,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: selectedFolder != null
                                ? AppTheme.amber.withValues(alpha: 0.6)
                                : Colors.transparent,
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              selectedFolder != null ? Icons.folder : Icons.folder_open_outlined,
                              color: AppTheme.amber,
                              size: 18,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                selectedFolder ?? 'Tap to pick a folder…',
                                style: TextStyle(
                                  color: selectedFolder != null
                                      ? AppTheme.textPrimary
                                      : AppTheme.textSecondary.withValues(alpha: 0.5),
                                  fontSize: 12,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                maxLines: 2,
                              ),
                            ),
                            const SizedBox(width: 6),
                            const Icon(
                              Icons.chevron_right,
                              color: AppTheme.textSecondary,
                              size: 16,
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // ── Video count dropdown ─────────────────
                    const Text(
                      'NUMBER OF VIDEOS',
                      style: TextStyle(
                        color: AppTheme.amber,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.8,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        color: AppTheme.bg,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<int>(
                          value: selectedCount,
                          dropdownColor: AppTheme.panel,
                          iconEnabledColor: AppTheme.amber,
                          style: const TextStyle(color: AppTheme.textPrimary, fontSize: 14),
                          items: List.generate(15, (i) => i + 1).map((n) {
                            return DropdownMenuItem(
                              value: n,
                              child: Text(
                                n == 1 ? '1 video' : '$n videos',
                                style: const TextStyle(color: AppTheme.textPrimary, fontSize: 14),
                              ),
                            );
                          }).toList(),
                          onChanged: (val) {
                            if (val != null) setDialogState(() => selectedCount = val);
                          },
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // ── Remember toggle ──────────────────────
                    GestureDetector(
                      onTap: () => setDialogState(() => remember = !remember),
                      child: Row(
                        children: [
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            width: 18,
                            height: 18,
                            decoration: BoxDecoration(
                              color: remember ? AppTheme.amber : Colors.transparent,
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(
                                color: remember ? AppTheme.amber : AppTheme.textSecondary,
                                width: 1.5,
                              ),
                            ),
                            child: remember
                                ? const Icon(Icons.check, size: 12, color: AppTheme.bg)
                                : null,
                          ),
                          const SizedBox(width: 10),
                          const Text(
                            'Remember these settings',
                            style: TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(null),
                  child: const Text(
                    'CANCEL',
                    style: TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 12,
                      letterSpacing: 1.2,
                    ),
                  ),
                ),
                ElevatedButton(
                  onPressed: selectedFolder == null
                      ? null // keep SEND disabled until a folder is chosen
                      : () {
                          Navigator.of(ctx).pop(
                            _VideoSettings(
                              folder: selectedFolder!,
                              count: selectedCount,
                              remember: remember,
                            ),
                          );
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.amber,
                    foregroundColor: AppTheme.bg,
                    disabledBackgroundColor: AppTheme.amber.withValues(alpha: 0.35),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                  ),
                  child: const Text(
                    'SEND',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 1.5),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  /// Scans [folderPath] for video files, validates counts, then uploads.
  Future<void> _uploadVideosFromFolder(String folderPath, int requestedCount) async {
    final vehicleId = _nameCtrl.text.trim();

    // ── Resolve content URI → real paths ────────────────────
    List<String> resolvedPaths;
    try {
      resolvedPaths = await FileUtils.getFilesFromUri(folderPath);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Could not read folder: $e')));
      }
      return;
    }

    final allVideoFiles = resolvedPaths.map((p) => File(p)).toList()
      ..sort((a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync())); // newest → oldest

    // ── Guard: no videos found ───────────────────────────────
    if (allVideoFiles.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No video files found in the selected folder.'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
      return;
    }

    // ── Warn if fewer files than requested ───────────────────
    final available = allVideoFiles.length;
    final count = requestedCount.clamp(1, available);

    if (available < requestedCount && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Only $available video${available == 1 ? '' : 's'} found '
            '(you requested $requestedCount). Uploading all $available.',
          ),
          backgroundColor: AppTheme.amber,
          duration: const Duration(seconds: 4),
        ),
      );
      await Future.delayed(const Duration(milliseconds: 600));
    }

    final videoFiles = allVideoFiles.take(count).toList();

    setState(() {
      _isUploadingVideos = true;
      _videoUploadProgress = 0;
      _videoUploadTotal = videoFiles.length;
    });

    int successCount = 0;
    for (final file in videoFiles) {
      try {
        await _service!.pushVideo(vehicleId, file);
        successCount++;
      } catch (e) {
        debugPrint('Video upload error for ${file.path}: $e');
      } finally {
        if (mounted) setState(() => _videoUploadProgress++);
      }
    }

    setState(() => _isUploadingVideos = false);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$successCount of ${videoFiles.length} video(s) uploaded successfully.'),
          backgroundColor: successCount == videoFiles.length ? AppTheme.green : AppTheme.amber,
        ),
      );
    }
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
            const SizedBox(height: 32),

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

            const SizedBox(height: 32),
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

        // ── Video upload progress overlay ─────────────────────
        if (_isUploadingVideos)
          Positioned.fill(
            child: Container(
              color: Colors.black.withValues(alpha: 0.55),
              child: Center(
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 40),
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: AppTheme.panel,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.cloud_upload_outlined, color: AppTheme.amber, size: 36),
                      const SizedBox(height: 16),
                      Text(
                        'Uploading Videos',
                        style: const TextStyle(
                          color: AppTheme.textPrimary,
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '$_videoUploadProgress / $_videoUploadTotal',
                        style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13),
                      ),
                      const SizedBox(height: 16),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: _videoUploadTotal > 0
                              ? _videoUploadProgress / _videoUploadTotal
                              : 0,
                          backgroundColor: AppTheme.bg,
                          color: AppTheme.amber,
                          minHeight: 6,
                        ),
                      ),
                    ],
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
                if (isRecording)
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      onPressed: _isBusy ? null : _stopRecording,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.red,
                        foregroundColor: Colors.white,
                        disabledBackgroundColor: AppTheme.red.withValues(alpha: 0.4),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        elevation: 0,
                      ),
                      child: _isBusy
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : const Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.stop_rounded, size: 18),
                                SizedBox(width: 8),
                                Text(
                                  'STOP RECORDING',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 2,
                                  ),
                                ),
                              ],
                            ),
                    ),
                  )
                else
                  Row(
                    children: [
                      // ── START LOCATION TRACKING ──────────
                      Expanded(
                        child: SizedBox(
                          height: 50,
                          child: ElevatedButton(
                            onPressed: _isBusy || _isUploadingVideos
                                ? null
                                : () => _startRecording(skipCamera: true),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppTheme.amber,
                              foregroundColor: AppTheme.bg,
                              disabledBackgroundColor: AppTheme.amber.withValues(alpha: 0.4),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              elevation: 0,
                            ),
                            child: _isBusy
                                ? SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: AppTheme.bg,
                                    ),
                                  )
                                : const Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(Icons.location_on_rounded, size: 18),
                                      SizedBox(width: 6),
                                      Flexible(
                                        child: Text(
                                          'START LOCATION TRACKING',
                                          style: TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w800,
                                            letterSpacing: 1,
                                          ),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ],
                                  ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),

                      // ── START TRIP STREAMING ─────────────
                      Expanded(
                        child: SizedBox(
                          height: 50,
                          child: ElevatedButton(
                            onPressed: _isBusy || _isUploadingVideos
                                ? null
                                : () => _startRecording(),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppTheme.amber,
                              foregroundColor: AppTheme.bg,
                              disabledBackgroundColor: AppTheme.amber.withValues(alpha: 0.4),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              elevation: 0,
                            ),
                            child: _isBusy
                                ? SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: AppTheme.bg,
                                    ),
                                  )
                                : const Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(Icons.fiber_manual_record, size: 18),
                                      SizedBox(width: 6),
                                      Flexible(
                                        child: Text(
                                          'START TRIP STREAMING',
                                          style: TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w800,
                                            letterSpacing: 1,
                                          ),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ],
                                  ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),

                      // ── SEND DEVICE VIDEOS ───────────────
                      Expanded(
                        child: SizedBox(
                          height: 50,
                          child: ElevatedButton(
                            onPressed: _isBusy || _isUploadingVideos ? null : _onSendDeviceVideos,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppTheme.amber,
                              foregroundColor: AppTheme.bg,
                              disabledBackgroundColor: AppTheme.amber.withValues(alpha: 0.4),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              elevation: 0,
                            ),
                            child: _isUploadingVideos
                                ? SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: AppTheme.bg,
                                    ),
                                  )
                                : const Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(Icons.video_collection, size: 18),
                                      SizedBox(width: 6),
                                      Flexible(
                                        child: Text(
                                          'SEND DEVICE VIDEOS',
                                          style: TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w800,
                                            letterSpacing: 1,
                                          ),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ],
                                  ),
                          ),
                        ),
                      ),
                    ],
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
// Video settings result object
// ─────────────────────────────────────────────────────────────

class _VideoSettings {
  final String folder;
  final int count;
  final bool remember;
  const _VideoSettings({required this.folder, required this.count, required this.remember});
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
            textAlign: TextAlign.center,
            style: TextStyle(
              color: isRecording ? Colors.white : AppTheme.bg,
              fontSize: 9,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        const SizedBox(height: 2),
        Icon(Icons.location_pin, color: isRecording ? AppTheme.red : AppTheme.amber, size: 24),
      ],
    );
  }
}
