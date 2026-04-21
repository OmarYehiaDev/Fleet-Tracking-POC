import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

class WebHomeWidget extends StatefulWidget {
  const WebHomeWidget({super.key});

  @override
  State<WebHomeWidget> createState() => _WebHomeWidgetState();
}

class _WebHomeWidgetState extends State<WebHomeWidget> {
  @override
  Widget build(BuildContext context) {
    return FlutterMap(
      options: MapOptions(
        initialCenter: LatLng(29.033607138928122, 31.119430465623736), // Center the map over Dar El Diayfa
        initialZoom: 9.2,
      ),
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.example.fleet_tracking_poc',
        ),
      ],
    );
  }
}
