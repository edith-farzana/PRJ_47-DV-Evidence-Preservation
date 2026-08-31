import 'package:flutter/material.dart';
import '../domain/pin_validator.dart';

class PinPage extends StatefulWidget {
  final VoidCallback onSuccess;

  const PinPage({
    super.key,
    required this.onSuccess,
  });

  @override
  State<PinPage> createState() => _PinPageState();
}

class _PinPageState extends State<PinPage> {
  final TextEditingController _controller = TextEditingController();
  final PinValidator _validator = const PinValidator();

  String _error = '';

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submitPin() {
    final pin = _controller.text.trim();

    if (_validator.isValid(pin)) {
      FocusScope.of(context).unfocus();
      widget.onSuccess();
      return;
    }

    setState(() {
      _error = 'Incorrect PIN';
    });

    _controller.clear();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B0712),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 82,
                  height: 82,
                  decoration: BoxDecoration(
                    color: const Color(0xFF6C3CEB),
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: const Icon(
                    Icons.lock_outline,
                    color: Colors.white,
                    size: 40,
                  ),
                ),

                const SizedBox(height: 28),

                const Text(
                  'Secure Evidence',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 30,
                    fontWeight: FontWeight.w700,
                  ),
                ),

                const SizedBox(height: 8),

                const Text(
                  'Enter PIN',
                  style: TextStyle(
                    color: Colors.white54,
                    fontSize: 15,
                  ),
                ),

                const SizedBox(height: 30),

                TextField(
                  controller: _controller,
                  keyboardType: TextInputType.number,
                  obscureText: false,
                  maxLength: 4,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 26,
                    letterSpacing: 8,
                  ),
                  decoration: InputDecoration(
                    counterText: '',
                    filled: true,
                    fillColor: const Color(0xFF171020),
                    hintText: 'PIN',
                    hintStyle: const TextStyle(
                      color: Colors.white24,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide.none,
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: const BorderSide(
                        color: Color(0xFF8B5CF6),
                        width: 1.5,
                      ),
                    ),
                  ),
                  onSubmitted: (_) => _submitPin(),
                ),

                if (_error.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text(
                    _error,
                    style: const TextStyle(
                      color: Colors.redAccent,
                      fontSize: 14,
                    ),
                  ),
                ],

                const SizedBox(height: 20),

                SizedBox(
                  width: double.infinity,
                  height: 54,
                  child: ElevatedButton(
                    onPressed: _submitPin,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF6C3CEB),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: const Text(
                      'Continue',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}