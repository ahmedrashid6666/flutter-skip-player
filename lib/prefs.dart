import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// a boolean preference that notifies listeners when it changes
abstract class BoolPref extends ChangeNotifier {
  final String name;
  final bool defaultValue;
  BoolPref({@required this.name, this.defaultValue}) {
    this._value = defaultValue;
  }

  bool _value;
  bool get value => _value;
  set value(bool newValue) {
    if (newValue == _value) return;
    _value = newValue;
    notifyListeners();
  }

  void linkTo(SharedPreferences sharedPrefs) {
    // load from preferences
    value = sharedPrefs.getBool(name) ?? defaultValue;
    // save back to preferences when modified
    addListener(() => sharedPrefs.setBool(name, value));
  }
}

/// preference for dark theme or light theme
class DarkPref extends BoolPref {
  DarkPref() : super(name: "darkMode", defaultValue: true);
}

/// preference for caching computed silences in .silence files next to the audio file
class CreateSilenceFilesPref extends BoolPref {
  CreateSilenceFilesPref() : super(name: "createSilenceFiles", defaultValue: true);
}
