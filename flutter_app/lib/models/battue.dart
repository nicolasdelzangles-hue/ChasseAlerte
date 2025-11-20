class Battue {
  final int id;
  final String title;
  final String location;
  final String date;
  final String imageUrl;
  final String description;
  final double latitude;
  final double longitude;
  final String type;
  final bool isPrivate;

  Battue({
    required this.id,
    required this.title,
    required this.location,
    required this.date,
    required this.imageUrl,
    required this.description,
    required this.latitude,
    required this.longitude,
    required this.type,
    required this.isPrivate,
  });

  factory Battue.fromJson(Map<String, dynamic> json) {
    return Battue(
      id: json['id'] as int,
      title: json['title'] as String,
      location: json['location'] as String,
      date: json['date'] as String,
      imageUrl: json['imageUrl'] as String? ?? '',
      description: json['description'] as String? ?? '',
      latitude: (json['latitude'] as num).toDouble(),
      longitude: (json['longitude'] as num).toDouble(),
      type: json['type'] as String,
      isPrivate: json['isPrivate'] == 1,  // si MySQL renvoie 0/1
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'location': location,
      'date': date,
      'imageUrl': imageUrl,
      'description': description,
      'latitude': latitude,
      'longitude': longitude,
      'type': type,
      'isPrivate': isPrivate ? 1 : 0,
    };
  }
}
