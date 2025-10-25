// lib/widgets/link_partner_dialog.dart
import 'package:flutter/material.dart';

class LinkPartnerDialog extends StatefulWidget {
  const LinkPartnerDialog({
    super.key,
    this.onSubmit, // optional: let the dialog handle linking if you want
    this.initialCode,
  });

  /// If provided, the dialog will call this and show a loading state until it completes.
  /// Return true to close the dialog, false to keep it open (e.g., invalid code).
  final Future<bool> Function(String code)? onSubmit;

  /// Optionally prefill a code.
  final String? initialCode;

  @override
  State<LinkPartnerDialog> createState() => _LinkPartnerDialogState();
}

class _LinkPartnerDialogState extends State<LinkPartnerDialog> {
  static const blue = Color(0xFF2d59f0);

  final _formKey = GlobalKey<FormState>();
  final _codeCtrl = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.initialCode != null) {
      _codeCtrl.text = widget.initialCode!;
    }
  }

  @override
  void dispose() {
    _codeCtrl.dispose();
    super.dispose();
  }

  String _normalize(String raw) => raw.trim();

  Future<void> _handleSubmit() async {
    setState(() => _error = null);

    if (!_formKey.currentState!.validate()) return;

    final code = _normalize(_codeCtrl.text);

    // If the caller provided a handler, run it with loading UI.
    if (widget.onSubmit != null) {
      try {
        setState(() => _loading = true);
        final ok = await widget.onSubmit!(code);
        if (!mounted) return;
        setState(() => _loading = false);
        if (ok) Navigator.pop(context, code);
        else setState(() => _error = "That code didn’t work. Try again.");
      } catch (_) {
        if (!mounted) return;
        setState(() {
          _loading = false;
          _error = "Something went wrong. Please try again.";
        });
      }
      return;
    }

    // Default behavior: just return the code to the caller.
    if (!mounted) return;
    Navigator.pop(context, code);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AlertDialog(
      backgroundColor: Colors.white,
      elevation: 8,
      surfaceTintColor: Colors.transparent, // no gray overlay tint
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      titlePadding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
      contentPadding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
      actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      title: Row(
        children: [
          Container(
            decoration: BoxDecoration(
              color: blue.withOpacity(0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            padding: const EdgeInsets.all(8),
            child: const Icon(Icons.person_add_alt_1_rounded, color: blue, size: 22),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              "Link Partner",
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Helper text
            Text(
              "Enter the partner code you received.",
              style: theme.textTheme.bodyMedium?.copyWith(color: Colors.black54),
            ),
            const SizedBox(height: 12),

            // Input
            TextFormField(
              controller: _codeCtrl,
              autofocus: true,
              textInputAction: TextInputAction.done,
              onFieldSubmitted: (_) => _handleSubmit(),
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                letterSpacing: 0.2,
              ),
              decoration: InputDecoration(
                hintText: "e.g. ABCD-1234",
                filled: true,
                fillColor: blue.withOpacity(0.06),
                prefixIcon: const Icon(Icons.qr_code_2_rounded, color: blue),
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: blue.withOpacity(0.25), width: 1.2),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: blue, width: 1.6),
                ),
                errorBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Colors.redAccent),
                ),
              ),
              validator: (v) {
                final code = _normalize(v ?? "");
                if (code.isEmpty) return "Please enter a partner code";
                if (code.length < 4) return "Code looks too short";
                return null;
              },
            ),

            if (_error != null) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  const Icon(Icons.error_outline, color: Colors.redAccent, size: 18),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      _error!,
                      style: const TextStyle(color: Colors.redAccent, fontSize: 13),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _loading ? null : () => Navigator.pop(context),
          style: TextButton.styleFrom(
            foregroundColor: Colors.grey.shade700,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
          child: const Text("Cancel"),
        ),
        ElevatedButton.icon(
          onPressed: _loading ? null : _handleSubmit,
          style: ElevatedButton.styleFrom(
            backgroundColor: blue,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            elevation: 0,
          ),
          icon: _loading
              ? const SizedBox(
            width: 18, height: 18,
            child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation(Colors.white)),
          )
              : const Icon(Icons.link_rounded, size: 18),
          label: Text(_loading ? "Linking..." : "Link"),
        ),
      ],
    );
  }
}
