import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:get/get_core/src/get_main.dart';
import 'package:medi_care/features/authentication/controllers.onboarding/onboarding_controller.dart';
import 'package:medi_care/features/authentication/screens/onboarding/widgets/onboarding_dot_navigation.dart';
import 'package:medi_care/features/authentication/screens/onboarding/widgets/onboarding_next_button.dart';
import 'package:medi_care/features/authentication/screens/onboarding/widgets/onboarding_page.dart';
import 'package:medi_care/features/authentication/screens/onboarding/widgets/onboarding_skip.dart';
import 'package:medi_care/utils/helpers/helper_functions.dart';

import '../../../../utils/constants/colors.dart';
import '../../../../utils/constants/image_strings.dart';
import '../../../../utils/constants/sizes.dart';
import '../../../../utils/constants/text_strings.dart';
import '../../../../utils/device/device_utility.dart';
import 'package:smooth_page_indicator/smooth_page_indicator.dart';

class OnBoardingScreen extends StatelessWidget {
  const OnBoardingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = Get.put(OnBoardingController());

    return Scaffold(
      body: Stack(
        children: [
          // Horizontal Scrollable Pages
          PageView(
            controller: controller.pageController,
            onPageChanged: controller.updatePageIndicator,
            children: const [
              OnboardingPage(
                image: TImages.onBoardingImage1,
                title: TTexts.onBoardingTitle1,
                subTitle: TTexts.onBoardingSubTitle1,
              ),
              OnboardingPage(
                image: TImages.onBoardingImage2,
                title: TTexts.onBoardingTitle2,
                subTitle: TTexts.onBoardingSubTitle2,
              ),
              OnboardingPage(
                image: TImages.onBoardingImage3,
                title: TTexts.onBoardingTitle3,
                subTitle: TTexts.onBoardingSubTitle3,
              ), // Column
            ],
          ), // PageView

          // Skip Button
          const OnBoardingSkip(), // Positioned

          // Dot Navigation SmoothPageIndicator
          const OnBoardingDotNavigation(), // Positioned

          // Circular Button
          const OnBoardingNextButton(), // Positioned
        ],
      ),
    );
  }
}




