import 'package:flutter/material.dart';

import '../domain/calculator_engine.dart';

class CalculatorPage extends StatefulWidget {
  const CalculatorPage({super.key, required this.onPrivateAccess});

  final VoidCallback onPrivateAccess;

  @override
  State<CalculatorPage> createState() => _CalculatorPageState();
}

class _CalculatorPageState extends State<CalculatorPage> {
  final CalculatorEngine _calculator = CalculatorEngine();

  String _privateSequence = '';

  // Temporary development sequence.
  //
  // This is only for testing the private-access routing.
  // We will replace this later with the final PIN/secret mechanism.
  static const String _developmentSecret = '1+2+3+4=';

  void _handleDigit(String digit) {
    setState(() {
      _calculator.inputDigit(digit);

      _privateSequence += digit;
      _trimPrivateSequence();
    });
  }

  void _handleDecimal() {
    setState(() {
      _calculator.inputDecimal();

      _privateSequence += '.';
      _trimPrivateSequence();
    });
  }

  void _handleOperator(String operator) {
    setState(() {
      _calculator.inputOperator(operator);

      _privateSequence += operator;
      _trimPrivateSequence();
    });
  }

  void _handleEquals() {
    setState(() {
      _privateSequence += '=';
      _trimPrivateSequence();

      if (_privateSequence == _developmentSecret) {
        _privateSequence = '';
        widget.onPrivateAccess();
        return;
      }

      _calculator.calculate();
    });
  }

  void _handleClear() {
    setState(() {
      _calculator.clear();
      _privateSequence = '';
    });
  }

  void _handleBackspace() {
    setState(() {
      _calculator.backspace();

      if (_privateSequence.isNotEmpty) {
        _privateSequence = _privateSequence.substring(
          0,
          _privateSequence.length - 1,
        );
      }
    });
  }

  void _handlePercentage() {
    setState(() {
      _calculator.percentage();

      _privateSequence += '%';
      _trimPrivateSequence();
    });
  }

  void _trimPrivateSequence() {
    const maxLength = 32;

    if (_privateSequence.length > maxLength) {
      _privateSequence = _privateSequence.substring(
        _privateSequence.length - maxLength,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(child: _buildDisplay()),
            _buildCalculatorPad(),
          ],
        ),
      ),
    );
  }

  Widget _buildDisplay() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 18),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (_calculator.expression.isNotEmpty)
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerRight,
              child: Text(
                _calculator.expression,
                style: const TextStyle(
                  color: Colors.white54,
                  fontSize: 26,
                  fontWeight: FontWeight.w300,
                ),
              ),
            ),
          const SizedBox(height: 8),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerRight,
            child: Text(
              _calculator.display,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 64,
                fontWeight: FontWeight.w300,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCalculatorPad() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 20),
      child: Column(
        children: [
          Row(
            children: [
              _button(
                label: 'AC',
                onPressed: _handleClear,
                type: _ButtonType.function,
              ),
              _button(
                label: '⌫',
                onPressed: _handleBackspace,
                type: _ButtonType.function,
              ),
              _button(
                label: '%',
                onPressed: _handlePercentage,
                type: _ButtonType.function,
              ),
              _button(
                label: '÷',
                onPressed: () => _handleOperator('÷'),
                type: _ButtonType.operator,
              ),
            ],
          ),
          Row(
            children: [
              _button(label: '7', onPressed: () => _handleDigit('7')),
              _button(label: '8', onPressed: () => _handleDigit('8')),
              _button(label: '9', onPressed: () => _handleDigit('9')),
              _button(
                label: '×',
                onPressed: () => _handleOperator('×'),
                type: _ButtonType.operator,
              ),
            ],
          ),
          Row(
            children: [
              _button(label: '4', onPressed: () => _handleDigit('4')),
              _button(label: '5', onPressed: () => _handleDigit('5')),
              _button(label: '6', onPressed: () => _handleDigit('6')),
              _button(
                label: '-',
                onPressed: () => _handleOperator('-'),
                type: _ButtonType.operator,
              ),
            ],
          ),
          Row(
            children: [
              _button(label: '1', onPressed: () => _handleDigit('1')),
              _button(label: '2', onPressed: () => _handleDigit('2')),
              _button(label: '3', onPressed: () => _handleDigit('3')),
              _button(
                label: '+',
                onPressed: () => _handleOperator('+'),
                type: _ButtonType.operator,
              ),
            ],
          ),
          Row(
            children: [
              Expanded(
                flex: 2,
                child: _calculatorButton(
                  label: '0',
                  onPressed: () => _handleDigit('0'),
                ),
              ),
              _button(label: '.', onPressed: _handleDecimal),
              _button(
                label: '=',
                onPressed: _handleEquals,
                type: _ButtonType.operator,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _button({
    required String label,
    required VoidCallback onPressed,
    _ButtonType type = _ButtonType.number,
  }) {
    return Expanded(
      child: _calculatorButton(label: label, onPressed: onPressed, type: type),
    );
  }

  Widget _calculatorButton({
    required String label,
    required VoidCallback onPressed,
    _ButtonType type = _ButtonType.number,
  }) {
    Color background;

    switch (type) {
      case _ButtonType.number:
        background = const Color(0xFF333333);
        break;

      case _ButtonType.function:
        background = const Color(0xFFA5A5A5);
        break;

      case _ButtonType.operator:
        background = const Color(0xFFFF9500);
        break;
    }

    return Padding(
      padding: const EdgeInsets.all(5),
      child: SizedBox(
        height: 72,
        child: Material(
          color: background,
          borderRadius: BorderRadius.circular(40),
          child: InkWell(
            borderRadius: BorderRadius.circular(40),
            onTap: onPressed,
            child: Center(
              child: Text(
                label,
                style: TextStyle(
                  color: type == _ButtonType.function
                      ? Colors.black
                      : Colors.white,
                  fontSize: 28,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

enum _ButtonType { number, function, operator }
