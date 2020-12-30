import 'package:flutter/foundation.dart';

class PreviousLocation {
  final String location;
  final String placeId;

  PreviousLocation({
    @required this.location,
    @required this.placeId,
  });

  Map<String, dynamic> toMap() {
    return {
      'location': location,
      'placeId': placeId,
    };
  }
}
