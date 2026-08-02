import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // Edge-to-edge with transparent bars: the graphite background runs under the
  // status and navigation bars instead of stopping at a grey strip.
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );

  // The counter has no landscape layout, and a rotating ring is not a feature.
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);

  runApp(const StepStepApp());
}
