import 'package:drift/drift.dart';

/// Local mirror of `profiles` (public-safe fields only — Section 6). Used
/// so the UI can render a sender's display name/avatar offline without a
/// round trip, and so notifications (Section 11.2) can show a name
/// without decrypting anything new.
class LocalProfiles extends Table {
  TextColumn get id => text()();
  TextColumn get username => text()();
  TextColumn get displayName => text()();
  TextColumn get avatarUrl => text().nullable()();
  DateTimeColumn get lastSeenAt => dateTime().nullable()();
  BoolColumn get isOnline => boolean().withDefault(const Constant(false))();
  DateTimeColumn get cachedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}
