// lib/features/authentication/screens/onboarding/onboarding_screen.dart
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:lottie/lottie.dart';
import 'package:smooth_page_indicator/smooth_page_indicator.dart';
import '../onboarding_controller.dart';

class OnBoardingScreen extends StatelessWidget {
  const OnBoardingScreen({super.key});

  static const _blue  = Color(0xFF2d59f0);
  static const _white = Colors.white;

  @override
  Widget build(BuildContext context) {
    final controller = Get.put(OnBoardingController());

    return Scaffold(
      backgroundColor: Colors.white,
      body: Stack(
        children: [
          // PAGES
          PageView(
            controller: controller.pageController,
            onPageChanged: controller.updatePageIndicator,
            children: const [
              _Slide(
                lottie: 'assets/animations/on_boarding/Onboarding_first_page.json',
                title: "Manage Medications",
                subtitle: "Easily add and manage medications with dosage reminders and schedules.",
              ),
              _Slide(
                lottie: 'assets/animations/on_boarding/Onboarding_second_page.json',
                title: "Track Patient Health",
                subtitle: "Monitor records, track medications, and keep comprehensive care logs.",
              ),
              _Slide(
                lottie: 'assets/animations/on_boarding/Onboarding_third_page.json',
                title: "Stay Organized",
                subtitle: "Get timely alerts for doses to provide seamless care.",
              ),
            ],
          ),

          // SKIP (top-right)
          Positioned(
            top: MediaQuery.of(context).padding.top + 8,
            right: 16,
            child: TextButton(
              onPressed: () async {
                await controller.markDone();
                if (!context.mounted) return;
                Navigator.pushReplacementNamed(context, '/welcome');
              },
              child: const Text(
                'Skip',
                style: TextStyle(
                  color: _blue,
                  fontWeight: FontWeight.w600,
                  fontSize: 16,
                ),
              ),
            ),
          ),

          // INDICATOR (bottom, inline with Next; leave 96px right gap for FAB)
          Positioned(
            bottom: 24 + MediaQuery.of(context).padding.bottom,
            left: 24,
            right: 54,
            child: Center(
              child: SmoothPageIndicator(
                controller: controller.pageController,
                count: 3,
                onDotClicked: controller.dotNavigationClick,
                effect: const SlideEffect(
                  spacing: 10, radius: 4, dotWidth: 24, dotHeight: 6,
                  dotColor: _white, activeDotColor: _blue,
                ),
              ),
            ),
          ),

          // NEXT — circular blue FAB with white arrow (bottom-right)
          Positioned(
            bottom: 16 + MediaQuery.of(context).padding.bottom,
            right: 16,
            child: Obx(() {
              final isLast = OnBoardingController.instance.currentPageIndex.value == 2;
              return FloatingActionButton(
                backgroundColor: _blue,
                foregroundColor: _white,
                elevation: 4,
                onPressed: () async {
                  if (isLast) {
                    await controller.markDone();                 // set onboarding_done = true
                    if (!context.mounted) return;
                    Navigator.pushReplacementNamed(context, '/welcome');
                  } else {
                    controller.nextPageOnly();                   // just go to next page
                  }
                },
                child: Icon(isLast ? Icons.check : Icons.arrow_forward),
              );
            }),
          ),
        ],
      ),
    );
  }
}

class _Slide extends StatelessWidget {
  final String lottie;
  final String title;
  final String subtitle;

  const _Slide({
    required this.lottie,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.of(context).padding.top;
    final bottom = MediaQuery.of(context).padding.bottom;

    return Padding(
      // EXTRA bottom padding so Next FAB doesn’t overlap subtitle
      padding: EdgeInsets.fromLTRB(24, top + 48, 24, bottom + 96),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Raise the animation (shorter Expanded)
          Expanded(
            child: Lottie.asset(
              lottie,
              fit: BoxFit.contain,
              repeat: true,
            ),
          ),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w800,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 16,
              color: Colors.black54,
              height: 1.35,
            ),
          ),
          // Spacer so the indicator + FAB below don’t cover text
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}
