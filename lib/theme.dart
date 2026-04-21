import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class AppTheme {
  static const bg = Color(0xFF0D0F12);
  static const panel = Color(0xFF1C1F25);
  static const amber = Color(0xFFF59E0B);
  static const green = Color(0xFF10B981);
  static const red = Color(0xFFEF4444);
  static const textPrimary = Color(0xFFF0F0F0);
  static const textSecondary = Color(0xFF6B7280);
  static const surface = Color(0xFF141619);
  static const panelBorder = Color(0xFF252830);
}

class AppConsts {
  static const mapTileUrl =
      'https://tiles.stadiamaps.com/tiles/alidade_smooth_dark/{z}/{x}/{y}.png'
      '?api_key=9e8eed59-e664-4612-912f-3e28390957a7';

  static final timeFormat = DateFormat('HH:mm:ss');
  static final timestampFormat = DateFormat('MMM d · HH:mm:ss');
  static final shortDateFormat = DateFormat('EEE, dd MMM yyyy');
  static final fullFormat = DateFormat('EEEE, dd-MM-yyyy · HH:mm:ss');
}
