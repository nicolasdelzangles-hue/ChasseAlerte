# ChasseAlerte – Application mobile

Application Flutter pour chasseurs et présidents de société de chasse.

## Fonctionnalités

- 🔐 Authentification par email + mot de passe
- 📍 Carte interactive avec localisation et battues proches
- 📋 Liste filtrable des battues disponibles
- 🧑‍💼 Profil utilisateur avec modification
- ✏️ Création de battues pour les administrateurs
- 📲 Notifications push (à venir)
- 📡 Communication API sécurisée avec JWT

---

## 🔧 Structure du projet Flutter

```bash
lib/
├── main.dart
├── models/
│   ├── user.dart
│   └── battue.dart
├── providers/
│   └── auth_provider.dart
├── services/
│   └── api_service.dart
├── screens/
│   ├── login_screen.dart
│   ├── home_screen.dart
│   ├── profile_screen.dart
│   ├── edit_profile_screen.dart
│   ├── battue_list_screen.dart
│   ├── battue_map_screen.dart
│   ├── create_battue_screen.dart
│   └── main_navigation.dart
