import 'package:material_ui/material_ui.dart';

/// Asks for the password of a protected PDF. Returns null if cancelled.
Future<String?> showPasswordDialog(BuildContext context) async {
  final text = TextEditingController();
  final result = await showDialog<String?>(
    context: context,
    barrierDismissible: false,
    builder: (context) => AlertDialog(
      title: const Text('Password required'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('This PDF is protected. Enter its password to open it.'),
          const SizedBox(height: 14),
          TextField(
            controller: text,
            autofocus: true,
            obscureText: true,
            keyboardType: TextInputType.visiblePassword,
            decoration: const InputDecoration(hintText: 'Password'),
            onSubmitted: (v) => Navigator.of(context).pop(v),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(null), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.of(context).pop(text.text), child: const Text('Open')),
      ],
    ),
  );
  return result;
}
