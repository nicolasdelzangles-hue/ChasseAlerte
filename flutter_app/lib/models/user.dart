// lib/models/user.dart
class User {
  final int? id;
  final String? firstName;
  final String? lastName;
  final String? name;
  final String? email;
  final String? phone;
  final String? address;
  final String? postalCode;
  final String? city;
  final String? permitNumber;
  final DateTime? createdAt;

  // <-- AJOUT
  final String? role; // 'admin' | 'user' | null

  const User({
    this.id,
    this.firstName,
    this.lastName,
    this.name,
    this.email,
    this.phone,
    this.address,
    this.postalCode,
    this.city,
    this.permitNumber,
    this.createdAt,
    this.role, // <-- AJOUT
  });

  factory User.fromJson(Map<String, dynamic> j) {
    String? _s(key1, [key2]) {
      final v = j[key1] ?? (key2 != null ? j[key2] : null);
      return v?.toString();
    }

    DateTime? _dt(key1, [key2]) {
      final v = j[key1] ?? (key2 != null ? j[key2] : null);
      return v == null ? null : DateTime.tryParse(v.toString());
    }

    return User(
      id: j['id'] is int ? j['id'] as int : int.tryParse('${j['id'] ?? ''}'),
      firstName: _s('first_name', 'firstName'),
      lastName:  _s('last_name', 'lastName'),
      name:      _s('name'),
      email:     _s('email'),
      phone:     _s('phone'),
      address:   _s('address'),
      postalCode:_s('postal_code', 'postalCode'),
      city:      _s('city'),
      permitNumber: _s('permit_number', 'permitNumber'),
      createdAt: _dt('created_at', 'createdAt'),
      role: _s('role'), // <-- AJOUT
    );
  }

  // pratique pour injecter le rôle depuis le token si l'API ne l’envoie pas
  User copyWith({String? role}) => User(
    id: id,
    firstName: firstName,
    lastName: lastName,
    name: name,
    email: email,
    phone: phone,
    address: address,
    postalCode: postalCode,
    city: city,
    permitNumber: permitNumber,
    createdAt: createdAt,
    role: role ?? this.role,
  );
}
