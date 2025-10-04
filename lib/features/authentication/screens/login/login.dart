import 'package:medi_care/utils/constants/colors.dart';
import 'package:medi_care/utils/constants/sizes.dart';
import 'package:medi_care/utils/constants/text_strings.dart';
import 'package:medi_care/utils/helpers/helper_functions.dart';
import 'package:flutter/material.dart';
import 'package:medi_care/common/Styles/spacing_styles.dart';

class LoginScreen extends StatelessWidget {
  const LoginScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final dark = THelperFunctions.isDarkMode(context);

    return Scaffold(
      body: SingleChildScrollView(
        child: Padding(
          padding: TSpacingStyles.paddingWithAppBarHeight,
          child: Column(
            children: [
              /// Logo, Title & Sub-Title
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Medical-themed icon instead of image
                  Container(
                    height: 150,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.medical_services,
                          size: 80,
                          color: dark ? TColors.white : TColors.primary,
                        ),
                        const SizedBox(height: TSizes.sm),
                        Text(
                          "MediCare",
                          style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                            color: dark ? TColors.white : TColors.primary,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: TSizes.lg),
                  Text(
                    TTexts.loginTitle,
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const SizedBox(height: TSizes.sm),
                  Text(
                    TTexts.loginSubTitle,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ],
              ),
              const SizedBox(height: TSizes.spaceBtwSections),

              /// Form
              Form(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      vertical: TSizes.spaceBtwSections),
                  child: Column(
                    children: [
                      /// Email
                      TextFormField(
                        decoration: const InputDecoration(
                            prefixIcon: Icon(Icons.email_outlined),
                            labelText: TTexts.email),
                      ),
                      const SizedBox(height: TSizes.spaceBtwInputFields),

                      /// Password
                      TextFormField(
                        obscureText: true,
                        decoration: const InputDecoration(
                          prefixIcon: Icon(Icons.password),
                          labelText: TTexts.password,
                          suffixIcon: Icon(Icons.remove_red_eye_outlined),
                        ),
                      ),
                      const SizedBox(height: TSizes.spaceBtwInputFields / 2),

                      /// Remember Me & Forget Password
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          /// Remember Me
                          Row(
                            children: [
                              Checkbox(value: true, onChanged: (value) {}),
                              const Text(TTexts.rememberMe),
                            ],
                          ),

                          /// Forget Password
                          TextButton(
                              onPressed: () {},
                              child: const Text(TTexts.forgetPassword)),
                        ],
                      ),
                      const SizedBox(height: TSizes.spaceBtwSections),

                      /// Sign in Button
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: () {},
                          child: const Text(TTexts.signIn),
                        ),
                      ),
                      const SizedBox(height: TSizes.spaceBtwItems),

                      /// Create Account Button
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton(
                          onPressed: () {},
                          child: const Text(TTexts.createAccount),
                        ),
                      ),
                      const SizedBox(height: TSizes.spaceBtwSections),

                      /// Divider
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Expanded(
                            child: Divider(
                              color: dark ? TColors.darkGrey : TColors.grey,
                              thickness: 0.5,
                              indent: 60,
                              endIndent: 5,
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 8.0),
                            child: Text(
                              TTexts.orSignInWith,
                              style: Theme.of(context).textTheme.labelMedium,
                            ),
                          ),
                          Expanded(
                            child: Divider(
                              color: dark ? TColors.darkGrey : TColors.grey,
                              thickness: 0.5,
                              indent: 5,
                              endIndent: 60,
                            ),
                          ),
                        ],
                      ),

                      /// Social Media Buttons (Optional - you can add later)
                      const SizedBox(height: TSizes.spaceBtwSections),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          // You can add social media buttons here later
                          Text(
                            "Secure medication management system",
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: TColors.darkGrey,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
