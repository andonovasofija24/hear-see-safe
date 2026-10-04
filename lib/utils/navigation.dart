import 'package:flutter/widgets.dart';

/// Глобален клуч на навигаторот - за враќање до главното мени и отворање
/// игра од било кој екран (ESC, гласовна команда со име на игра).
final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>();