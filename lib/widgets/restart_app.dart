import 'package:flutter/material.dart';

/// Używane po zmianach wymagających pełnego odświeżenia stanu, np. zmiana API.
class RestartApp extends StatefulWidget {
  const RestartApp({super.key, required this.child});

  final Widget child;

  static void restart(BuildContext context) {
    context.findAncestorStateOfType<_RestartAppState>()?.restart();
  }

  @override
  State<RestartApp> createState() => _RestartAppState();
}

class _RestartAppState extends State<RestartApp> {
  Key _key = UniqueKey();

  void restart() {
    setState(() {
      _key = UniqueKey();
    });
  }

  @override
  Widget build(BuildContext context) {
    return KeyedSubtree(key: _key, child: widget.child);
  }
}
