import 'package:google_maps_place_picker/src/models/previous_location.dart';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

class PreviousSearchListProvider {
  Database db;

  Future open({String path}) async {
    db = await openDatabase(
      join(await getDatabasesPath(), path),
      version: 1,
      onCreate: (Database db, int version) async {
        print('Run create table........');
        await db.execute(
            '''create table location (location text not null, placeId text unique not null )''');
      },
    );
  }

  Future<void> insertLocation(PreviousLocation location) async {
    print('Insert calling....');
    await db.insert(
      'location',
      location.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    print('Insert called');
  }

  Future<List<PreviousLocation>> getPreviousSearchItems() async {
    print('Read calling....');
    final List<Map<String, dynamic>> maps = await db.query('location');
    print('Read called');

    var locationList = List.generate(maps.length, (i) {
      return PreviousLocation(
        location: maps[i]['location'],
        placeId: maps[i]['placeId'],
      );
    });
    return locationList;
  }

  Future close() async => db.close();
}
