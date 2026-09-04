class CalculatorEngine {
  String _display = '0';
  String _expression = '';

  double? _storedValue;
  String? _pendingOperator;

  bool _waitingForOperand = false;
  bool _justCalculated = false;

  String get display => _display;
  String get expression => _expression;

  void inputDigit(String digit) {
    if (_display == 'Error') {
      clear();
    }

    if (_waitingForOperand || _justCalculated) {
      _display = digit;
      _waitingForOperand = false;
      _justCalculated = false;
      return;
    }

    if (_display == '0') {
      _display = digit;
    } else {
      _display += digit;
    }
  }

  void inputDecimal() {
    if (_display == 'Error') {
      clear();
    }

    if (_waitingForOperand || _justCalculated) {
      _display = '0.';
      _waitingForOperand = false;
      _justCalculated = false;
      return;
    }

    if (!_display.contains('.')) {
      _display += '.';
    }
  }

  void inputOperator(String operator) {
    if (_display == 'Error') {
      return;
    }

    final currentValue = double.tryParse(_display);

    if (currentValue == null) {
      return;
    }

    // If an operator is already waiting and the user presses
    // another operator, simply replace the operator.
    if (_pendingOperator != null && _waitingForOperand) {
      _pendingOperator = operator;
      _updateExpression();
      return;
    }

    if (_pendingOperator == null) {
      _storedValue = currentValue;
    } else {
      final result = _performCalculation(
        _storedValue!,
        currentValue,
        _pendingOperator!,
      );

      if (result == null) {
        return;
      }

      _storedValue = result;
      _display = _formatResult(result);
    }

    _pendingOperator = operator;
    _waitingForOperand = true;
    _justCalculated = false;

    _updateExpression();
  }

  void calculate() {
    if (_pendingOperator == null || _storedValue == null) {
      return;
    }

    final secondValue = double.tryParse(_display);

    if (secondValue == null) {
      return;
    }

    final result = _performCalculation(
      _storedValue!,
      secondValue,
      _pendingOperator!,
    );

    if (result == null) {
      return;
    }

    final left = _formatResult(_storedValue!);
    final right = _formatResult(secondValue);
    final operator = _displayOperator(_pendingOperator!);
    final answer = _formatResult(result);

    _expression = '$left $operator $right =';
    _display = answer;

    _storedValue = result;
    _pendingOperator = null;
    _waitingForOperand = false;
    _justCalculated = true;
  }

  double? _performCalculation(double first, double second, String operator) {
    switch (operator) {
      case '+':
        return first + second;

      case '-':
        return first - second;

      case '×':
        return first * second;

      case '÷':
        if (second == 0) {
          _display = 'Error';
          _expression = 'Cannot divide by zero';

          _storedValue = null;
          _pendingOperator = null;
          _waitingForOperand = true;
          _justCalculated = false;

          return null;
        }

        return first / second;

      default:
        return null;
    }
  }

  void clear() {
    _display = '0';
    _expression = '';

    _storedValue = null;
    _pendingOperator = null;

    _waitingForOperand = false;
    _justCalculated = false;
  }

  void backspace() {
    if (_display == 'Error' || _justCalculated) {
      clear();
      return;
    }

    if (_waitingForOperand) {
      return;
    }

    if (_display.length <= 1) {
      _display = '0';
      return;
    }

    _display = _display.substring(0, _display.length - 1);

    if (_display == '-' || _display.isEmpty) {
      _display = '0';
    }
  }

  void percentage() {
    if (_display == 'Error') {
      return;
    }

    final value = double.tryParse(_display);

    if (value == null) {
      return;
    }

    _display = _formatResult(value / 100);
  }

  void _updateExpression() {
    if (_storedValue == null || _pendingOperator == null) {
      _expression = '';
      return;
    }

    final value = _formatResult(_storedValue!);
    final operator = _displayOperator(_pendingOperator!);

    _expression = '$value $operator';
  }

  String _displayOperator(String operator) {
    switch (operator) {
      case '×':
        return '×';

      case '÷':
        return '÷';

      default:
        return operator;
    }
  }

  String _formatResult(double value) {
    if (value.isNaN || value.isInfinite) {
      return 'Error';
    }

    if (value == value.roundToDouble()) {
      return value.toInt().toString();
    }

    return value
        .toStringAsFixed(10)
        .replaceFirst(RegExp(r'0+$'), '')
        .replaceFirst(RegExp(r'\.$'), '');
  }
}
