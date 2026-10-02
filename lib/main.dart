import 'package:flutter/material.dart';

import 'app.dart';
import 'data/services.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Everything is stored on the device in SQLite; there is no network setup.
  final services = await Services.boot();

  runApp(WizardApp(services: services));
}
