import 'package:flutter/material.dart';

class UserRole {
  String name; // editable
  final Color color;
  final IconData icon;

  UserRole({
    required this.name,
    required this.color,
    required this.icon,
  });
}