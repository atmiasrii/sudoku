# Workspace AI Agent Instructions

## Overview
This workspace contains a Sudoku app with a Flutter frontend and a Node.js/Express backend. The backend uses Supabase for data storage. The project is structured for both local development and future expansion (multiplayer, rating, etc.).

## Build & Run Commands

### Flutter App
- **Run app (dev):**
  ```
  flutter run
  ```
- **Test (Flutter):**
  ```
  flutter test
  ```

### Backend (Node.js/Express)
- **Install dependencies:**
  ```
  cd backend
  npm install
  ```
- **Run server:**
  ```
  npm start
  ```
- **Dev mode:**
  ```
  npm run dev
  ```

## Project Structure
- `lib/` — Flutter app source
- `backend/` — Node.js backend (Express, Supabase)
- `test/` — Flutter widget tests

## Conventions
- **Frontend:**
  - Use Dart/Flutter best practices
  - UI logic in `screens/`, widgets in `widgets/`, business logic in `logic/`, models in `models/`
- **Backend:**
  - Use Express routers/controllers/services pattern
  - Supabase config in `backend/config/supabase.js`
  - Environment variables in `.env` (not committed)

## Pitfalls
- Ensure `.env` is set up for backend (see `backend/config/supabase.js`)
- Flutter and Node.js must be installed for full-stack development
- No backend tests yet—add tests in `backend/` as needed

## Example Prompts
- "Build and run the Flutter app."
- "Start the backend server."
- "Add a new API route for Sudoku puzzles."
- "Write a test for the Sudoku solver."

## Next Customizations
- Add backend test instructions and test runner integration
- Separate agent instructions for frontend (`lib/`) and backend (`backend/`) if complexity grows
