import 'package:equatable/equatable.dart';

class AppUser extends Equatable {
  const AppUser({
    required this.id,
    required this.username,
    required this.displayName,
    this.avatarUrl,
  });

  final String id;
  final String username;
  final String displayName;
  final String? avatarUrl;

  @override
  List<Object?> get props => [id, username, displayName, avatarUrl];
}
