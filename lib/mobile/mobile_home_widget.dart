import 'package:flutter/material.dart';

import '../models.dart';

class MobileHomeWidget extends StatefulWidget {
  const MobileHomeWidget({super.key});

  @override
  State<MobileHomeWidget> createState() => _MobileHomeWidgetState();
}

class _MobileHomeWidgetState extends State<MobileHomeWidget> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  late TextEditingController _vehicleNameController;
  RecordingState? state;
  bool get _isIdle => state == RecordingState.idle;
  bool get _isRecording => state == RecordingState.recording;
  bool get _pauseRecording => state == RecordingState.paused;
  bool get _hasError => state == RecordingState.error;
  // bool _isLoading = false;
  String _vehicleName = '';

  @override
  void initState() {
    super.initState();
    _vehicleNameController = TextEditingController();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Builder(
          builder: (context) {
            if (state != null) {
              return Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    spacing: 16,
                    children: [
                      Text('Vehicle name: $_vehicleName'),
                      TextButton.icon(
                        onPressed: () {
                          setState(() {
                            state = null;
                            _vehicleNameController.text = _vehicleName;
                            _vehicleName = '';
                          });
                        },
                        label: Text("Change vehicle"),
                        icon: Icon(Icons.change_circle),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  if (_isIdle) const Text('You can start recording now!'),
                  if (_isRecording) const Text('Recording in progress...'),
                  if (_pauseRecording) const Text('Recording paused'),
                  if (_hasError) const Text('An error occurred while recording'),
                ],
              );
            }
            return Form(
              key: _formKey,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text('Enter the name of your vehicle to start recording'),
                  Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: _vehicleNameController,
                            autovalidateMode: AutovalidateMode.onUserInteractionIfError,
                            validator: (value) {
                              if (value == null || value.isEmpty) {
                                return 'Please enter a name for your vehicle';
                              } else if (value.length < 8) {
                                return 'Vehicle name must be at least 8 characters long';
                              } else if (value.contains(" ")) {
                                return 'Vehicle name must not contain spaces';
                              } else if (value.length > 20) {
                                return 'Vehicle name must be less than 20 characters long';
                              }
                              return null;
                            },
                            decoration: const InputDecoration(
                              border: OutlineInputBorder(),
                              labelText: 'Vehicle name',
                            ),
                          ),
                        ),
                        SizedBox(width: 16),
                        IconButton(
                          onPressed: () {
                            final fieldStatus = _formKey.currentState?.validate();
                            if (fieldStatus == null) return;
                            if (fieldStatus == false) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Please fix the errors in the form')),
                              );
                            }
                            setState(() {
                              _vehicleName = _vehicleNameController.text;
                              state = RecordingState.idle;
                            });
                          },
                          icon: Icon(Icons.send),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
      persistentFooterAlignment: AlignmentDirectional.center,
      persistentFooterButtons: [
        if (_vehicleName.isNotEmpty) ...[
          FloatingActionButton.extended(
            onPressed: () {
              setState(() {
                if (_isIdle) {
                  state = RecordingState.recording;
                } else if (_isRecording) {
                  state = RecordingState.paused;
                } else if (_pauseRecording) {
                  state = RecordingState.recording;
                } else if (_hasError) {
                  state = RecordingState.idle;
                }
              });
            },
            label: Text(
              _isIdle
                  ? 'Start recording'
                  : _isRecording
                  ? 'Pause recording'
                  : _pauseRecording
                  ? 'Resume recording'
                  : _hasError
                  ? 'Retry'
                  : 'Start recording',
            ),
            icon: Icon(_isRecording ? Icons.pause : Icons.fiber_manual_record),
          ),
        ],
        if (state != null && !_isIdle) ...[
          FloatingActionButton.extended(
            backgroundColor: Colors.red,
            foregroundColor: Colors.white,
            onPressed: () {
              setState(() => state = RecordingState.idle);
            },
            label: Text('Stop recording'),
            icon: Icon(Icons.stop),
          ),
        ],
      ],
    );
  }
}
