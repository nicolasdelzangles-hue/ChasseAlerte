String _ts() => DateTime.now().toIso8601String();
void logI(String tag, Object? msg) => print('[${_ts()}][$tag] $msg');
