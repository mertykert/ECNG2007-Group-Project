import 'package:Medi_Care/utils/constants/colors.dart';
import 'package:Medi_Care/utils/constants/image_strings.dart';
import 'package:Medi_Care/utils/constants/sizes.dart';
import 'package:Medi_Care/utils/constants/text_strings.dart';
import 'package:Medi_Care/utils/helpers/helper_functions.dart';
import 'package:flutter/material.dart';
import 'package:Medi_Care/common/Styles/spacing_styles.dart';

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
                  Image(
                    height: 150,
                    image: AssetImage(
                        dark ? TImages.lightAppLogo : TImages.darkAppLogo),
                  ), // Image
                  Text(TTexts.loginTitle,
                      style: Theme.of(context).textTheme.headlineMedium),
                  const SizedBox(height: TSizes.sm),
                  Text(TTexts.loginSubTitle,
                      style: Theme.of(context).textTheme.bodyMedium),
                ], // Column children
              ), // Column
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
                      ), // TextFormField
                      const SizedBox(height: TSizes.spaceBtwInputFields),

                      /// Password
                      TextFormField(
                        decoration: const InputDecoration(
                          prefixIcon: Icon(Icons.password),
                          labelText: TTexts.password,
                          suffixIcon: Icon(Icons.remove_red_eye_outlined),
                        ), // InputDecoration
                      ), // TextFormField
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
                          ), // Row

                          /// Forget Password
                          TextButton(
                              onPressed: () {},
                              child: const Text(TTexts.forgetPassword)),
                        ],
                      ), // Row
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
                    ], // Column children
                  ), // Column
                ), // Padding
              ), // Form
            ], // Main Column children
          ), // Column
        ), // Padding
      ), // SingleChildScrollView
    ); // Scaffold
  }
}
