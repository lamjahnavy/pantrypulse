# Pantry Pulse – Smart Pantry AI

A Flutter app that tracks pantry items and their expiry dates by scanning
product packs, and suggests recipes from what you already have.

## Features
- **Scan products** – photograph the front and back of a pack; the app reads
  brand, product name, MFD, expiry, quantity and price.
- **Pantry tracking** – see items nearing expiry and what has expired.
- **Chef AI recipes** – ask for any recipe (Normal Chat), or get recipes that
  use your soon-to-expire items first (Pantry Cooking).
- **Shopping list and meal planner**, with Firebase sign-in and sync.

## How it works
| Part | Technology |
|---|---|
| Mobile app | Flutter (Android) |
| OCR backend | Python, Flask, Keras-OCR + our custom-trained date recognizer |
| Recipe backend | Python, Flask on Render – Gemini (free tier), Groq fallback |
| Auth & storage | Firebase |

All label fields (dates, quantity, price, brand, name) are extracted by our
own OCR pipeline. Only when our OCR is unsure of the brand or product name
does the app use a Gemini vision fallback. Dates always come from local OCR.

## Project structure
Smart_Pantry_AI/
├── lib/            Flutter app (screens, OCR parsing, API clients)
├── ocr_backend/    OCR server, training and evaluation scripts
├── recipe_agent/   Recipe + product-identification server
└── test/           Flutter tests
render.yaml         Render deployment config

## Run locally
1. Copy `.env.example` to `.env` and add your API keys.
2. Start the OCR backend:  `python -m ocr_backend.app`  (port 8000)
3. Start the recipe backend: `python -m recipe_agent.app` (port 8001)
4. Connect the phone and forward ports:
   `adb reverse tcp:8000 tcp:8000` and `adb reverse tcp:8001 tcp:8001`
5. Run the app: `flutter run`

## Tests
pytest recipe_agent
flutter test

## Team
K Janshi
L Jahnavy
