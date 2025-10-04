import 'package:flutter/material.dart';

class SignUpScreen extends StatefulWidget {
  const SignUpScreen({super.key});

  @override
  State<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends State<SignUpScreen> {
  final _formKey = GlobalKey<FormState>();

  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmPasswordController = TextEditingController();

  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  bool _agree = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // Top gradient image
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Image.asset(
              "assets/images/topblue.png", // your blue top image
              fit: BoxFit.cover,
              height: 250,
            ),
          ),

          // Bottom gradient image
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Image.asset(
              "assets/images/bottomblue.png", // your blue bottom image
              fit: BoxFit.cover,
              height: 150,
            ),
          ),

          // Content
          SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 50),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Logo
                Align(
                  alignment: Alignment.topRight,
                  child: Image.asset(
                    "assets/images/medcross.png",
                    width: 60,
                    height: 60,
                  ),
                ),

                const SizedBox(height: 40),

                const Text(
                  "Create your account",
                  style: TextStyle(
                    fontFamily: "Poppins",
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Text(
                  "Start your journey with us",
                  style: TextStyle(
                      fontFamily: "Poppins",
                      fontSize: 16,
                      color: Colors.grey
                  ),
                ),

                const SizedBox(height: 30),

                Form(
                  key: _formKey,
                  child: Column(
                    children: [
                      // Full Name
                      TextFormField(
                        controller: _nameController,
                        decoration:  InputDecoration(
                          labelText: "Full Name",
                          labelStyle: const TextStyle(
                            fontFamily: 'Poppins', // Replace with your font family
                            fontSize: 16,                 // Optional: change font size
                            fontWeight: FontWeight.normal,   // Optional: change font weight
                            color: Colors.black,           // Optional: change label color
                          ),
                          prefixIcon: const Icon(Icons.person_outline),
                          // Default border
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(15),
                          ),

                          // Border when NOT focused
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(15),
                            borderSide: const BorderSide(
                              color: Colors.grey, // Default border color
                              width: 1.0,
                            ),
                          ),

                          // FocusedBorder
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(15),
                            borderSide: const BorderSide(
                              color: Color(0xFF2d59f0), // Active border color
                              width: 2.0,
                            ),
                          ),
                        ),
                        validator: (value) =>
                        value!.isEmpty ? "Enter your name" : null,
                      ),
                      const SizedBox(height: 20),

                      // Email

                      TextFormField(
                        controller: _emailController,
                        keyboardType: TextInputType.emailAddress,
                        decoration: InputDecoration(
                          labelText: "Email Address",
                          labelStyle: const TextStyle(
                            fontFamily: 'Poppins', // Replace with your font family
                            fontSize: 16,                 // Optional: change font size
                            fontWeight: FontWeight.normal,   // Optional: change font weight
                            color: Colors.black,           // Optional: change label color
                          ),
                          prefixIcon: const Icon(Icons.email_outlined),

                          // Default border
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(15),
                          ),

                          // Border when NOT focused
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(15),
                            borderSide: const BorderSide(
                              color: Colors.grey, // Default border color
                              width: 1.0,
                            ),
                          ),

                          // FocusedBorder
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(15),
                            borderSide: const BorderSide(
                              color: Color(0xFF2d59f0), // Active border color
                              width: 2.0,
                            ),
                          ),
                        ),
                        validator: (value) =>
                        value!.isEmpty ? "Enter your email" : null,
                      ),
                      const SizedBox(height: 20),


                      // Password
                      TextFormField(
                        controller: _passwordController,
                        obscureText: _obscurePassword,
                        decoration: InputDecoration(
                          labelText: "Password",
                          labelStyle: const TextStyle(
                            fontFamily: 'Poppins', // Replace with your font family
                            fontSize: 16,                 // Optional: change font size
                            fontWeight: FontWeight.normal,   // Optional: change font weight
                            color: Colors.black,           // Optional: change label color
                          ),
                          prefixIcon: const Icon(Icons.lock_outline),
                          // Default border
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(15),
                          ),

                          // Border when NOT focused
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(15),
                            borderSide: const BorderSide(
                              color: Colors.grey, // Default border color
                              width: 1.0,
                            ),
                          ),

                          // FocusedBorder
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(15),
                            borderSide: const BorderSide(
                              color: Color(0xFF2d59f0), // Active border color
                              width: 2.0,
                            ),
                          ),
                          suffixIcon: IconButton(
                            icon: Icon(_obscurePassword
                                ? Icons.visibility_off
                                : Icons.visibility),
                            onPressed: () {
                              setState(() {
                                _obscurePassword = !_obscurePassword;
                              });
                            },
                          ),
                        ),
                        validator: (value) => value!.length < 6
                            ? "Password must be at least 6 characters"
                            : null,
                      ),
                      const SizedBox(height: 20),

                      // Confirm Password
                      TextFormField(
                        controller: _confirmPasswordController,
                        obscureText: _obscureConfirmPassword,
                        decoration: InputDecoration(
                          labelText: "Confirm Password",
                          labelStyle: const TextStyle(
                            fontFamily: 'Poppins', // Replace with your font family
                            fontSize: 16,                 // Optional: change font size
                            fontWeight: FontWeight.normal,   // Optional: change font weight
                            color: Colors.black,           // Optional: change label color
                          ),
                          prefixIcon: const Icon(Icons.lock_outline),
                          // Default border
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(15),
                          ),

                          // Border when NOT focused
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(15),
                            borderSide: const BorderSide(
                              color: Colors.grey, // Default border color
                              width: 1.0,
                            ),
                          ),

                          // FocusedBorder
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(15),
                            borderSide: const BorderSide(
                              color: Color(0xFF2d59f0), // Active border color
                              width: 2.0,
                            ),
                          ),
                          suffixIcon: IconButton(
                            icon: Icon(_obscureConfirmPassword
                                ? Icons.visibility_off
                                : Icons.visibility),
                            onPressed: () {
                              setState(() {
                                _obscureConfirmPassword =
                                !_obscureConfirmPassword;
                              });
                            },
                          ),
                        ),
                        validator: (value) => value != _passwordController.text
                            ? "Passwords do not match"
                            : null,
                      ),
                      const SizedBox(height: 45),

                      // Terms & Privacy
                      Row(
                        children: [
                          Checkbox(
                            value: _agree,
                            onChanged: (value) {
                              setState(() {
                                _agree = value ?? false;
                              });
                            },
                          ),
                          const Expanded(
                            child: Text.rich(
                              TextSpan(
                                text: "I agree to Terms & Privacy. ",
                                children: [
                                  TextSpan(
                                    text: "Terms & Privacy",
                                    style: TextStyle(
                                      color: Colors.blue,
                                      decoration: TextDecoration.underline,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),

                      // Sign Up Button
                      const SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: Text(
                          "Sign Up",
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                      ),

                      const SizedBox(height: 20),
                      // Already have account?
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Text("Already have an account? "),
                          GestureDetector(
                            onTap: () {
                              Navigator.pop(context); // back to sign in
                            },
                            child: const Text(
                              "Login Here",
                              style: TextStyle(
                                color: Colors.blue,
                                decoration: TextDecoration.underline,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 200),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
