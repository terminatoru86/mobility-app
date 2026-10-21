import 'dart:convert';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

/// Live weather from Open-Meteo (free, no key).
class Weather {
  final double temp;
  final int code; // WMO weather code
  final double wind; // km/h
  final double gusts;
  final double windDir; // degrees, where the wind comes FROM
  final List<DateTime> times; // next hours, every 15 min
  final List<double> rain; // mm per 15 min
  final List<int> rainChance; // % per hour for the next hours
  final int? humidity; // %
  const Weather(this.temp, this.code, this.wind, this.gusts, this.windDir, this.times, this.rain, this.rainChance,
      {this.humidity});

  /// Minutes until rain starts in the next 2 h (null = no rain coming).
  int? get rainInMinutes {
    final now = DateTime.now();
    for (int k = 0; k < times.length; k++) {
      if (rain[k] >= 0.1) {
        final m = times[k].difference(now).inMinutes;
        if (m > 120) return null;
        return m < 0 ? 0 : m;
      }
    }
    return null;
  }

  String get windFrom {
    const names = ['N', 'NE', 'E', 'SE', 'S', 'SW', 'W', 'NW'];
    return names[((windDir % 360) / 45).round() % 8];
  }

  String get sky => switch (code) {
        0 => 'Clear',
        1 || 2 => 'Partly cloudy',
        3 => 'Cloudy',
        45 || 48 => 'Fog',
        >= 51 && <= 67 => 'Rain',
        >= 71 && <= 77 => 'Snow',
        >= 80 && <= 82 => 'Showers',
        >= 95 => 'Storm',
        _ => 'Cloudy',
      };
}

Future<Weather?> fetchWeather(LatLng p) async {
  final uri = Uri.https('api.open-meteo.com', '/v1/forecast', {
    'latitude': p.latitude.toStringAsFixed(3),
    'longitude': p.longitude.toStringAsFixed(3),
    'current': 'temperature_2m,relative_humidity_2m,weather_code,wind_speed_10m,wind_direction_10m,wind_gusts_10m',
    'minutely_15': 'precipitation',
    'hourly': 'precipitation_probability',
    'forecast_hours': '3',
    'forecast_minutely_15': '8',
    'timezone': 'auto',
  });
  try {
    final r = await http.get(uri).timeout(const Duration(seconds: 12));
    if (r.statusCode != 200) return null;
    final j = jsonDecode(r.body) as Map<String, dynamic>;
    final c = j['current'] as Map<String, dynamic>;
    final m = j['minutely_15'] as Map<String, dynamic>? ?? {};
    final h = j['hourly'] as Map<String, dynamic>? ?? {};
    return Weather(
      (c['temperature_2m'] as num).toDouble(),
      (c['weather_code'] as num).toInt(),
      (c['wind_speed_10m'] as num).toDouble(),
      (c['wind_gusts_10m'] as num? ?? 0).toDouble(),
      (c['wind_direction_10m'] as num? ?? 0).toDouble(),
      [for (final t in (m['time'] as List? ?? [])) DateTime.parse(t as String)],
      [for (final v in (m['precipitation'] as List? ?? [])) (v as num? ?? 0).toDouble()],
      [for (final v in (h['precipitation_probability'] as List? ?? [])) (v as num? ?? 0).toInt()],
      humidity: (c['relative_humidity_2m'] as num?)?.toInt(),
    );
  } catch (e) {
    debugPrint('Weather failed: $e');
    return null;
  }
}
