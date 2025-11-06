// lib/features/authentication/controllers.onboarding/onboarding_controller.dart
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';
import './screens/welcome/welcome.dart';

class OnBoardingController extends GetxController {
  static OnBoardingController get instance => Get.find();

  final pageController = PageController();
  Rx<int> currentPageIndex = 0.obs;

  Future<void> markDone() async {
    final p = await SharedPreferences.getInstance();
    await p.setBool('onboarding_done', true);
  }

  void updatePageIndicator(int index) => currentPageIndex.value = index;

  void dotNavigationClick(int index) {
    currentPageIndex.value = index;
    pageController.animateToPage(index,
        duration: const Duration(milliseconds: 280), curve: Curves.easeOut);
  }

// Keep page-advance logic only; no navigation here.
  void nextPageOnly() {
    final i = currentPageIndex.value;
    pageController.animateToPage(
      (i >= 2) ? 2 : i + 1,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOut,
    );
  }
}