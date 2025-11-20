# ChasseAlerte – Backend API

API Node.js Express pour l'application mobile **ChasseAlerte**.

## Fonctionnalités

- Authentification par email + mot de passe (`POST /api/auth/login`)
- Récupération du profil utilisateur (`GET /api/users/me`)
- Mise à jour du profil (`PUT /api/users/me`)
- Récupération des battues (`GET /api/battues`)
- Inscription à une battue (`POST /api/battues/:id/join`)
- Création d’une battue (`POST /api/battues`)

## Installation

```bash
cd backend
npm install
node index.js
