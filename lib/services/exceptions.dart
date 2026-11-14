class AppException implements Exception {
  final String message;
  AppException(this.message);
  @override
  String toString() => message;
}

class NetworkException extends AppException {
  NetworkException(String msg) : super(msg);
}

class ParseException extends AppException {
  ParseException(String msg) : super(msg);
}

class StorageException extends AppException {
  StorageException(String msg) : super(msg);
}

class RuleFormatException extends AppException {
  RuleFormatException(String msg) : super(msg);
}
