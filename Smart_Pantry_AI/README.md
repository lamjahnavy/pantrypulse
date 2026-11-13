# Pantry Pulse

Flutter pantry app with two Python backends:

- **OCR backend** (`ocr_backend/`, port `8000`, runs locally): Keras-OCR plus a
  custom-trained date recognizer reads package labels. The app parses brand,
  product name, MFD/EXP, quantity and price from the OCR text.
- **Recipe backend** (`recipe_agent/`, port `8001`, hosted on Render via
  `render.yaml`): generates recipes with Gemini (free tier), falling back to
  Groq (free tier) when every Gemini model fails. Its `/identify-product`
  endpoint is a vision fallback the app calls only when local OCR is unsure
  of a pack's brand or product name; dates always come from local OCR.

## Recipe backend configuration

Copy `.env.example` to `.env` and fill keys only in the ignored `.env` file.
Never commit or print `.env`. On Render, set the same values under the
service's Environment tab.

| Variable | Purpose | Default |
|---|---|---|
| `GEMINI_API_KEY` | Gemini API key | required |
| `RECIPE_GEMINI_MODEL` | Primary Gemini model | `gemini-3.5-flash` |
| `RECIPE_GEMINI_FALLBACK_MODELS` | Comma-separated models tried next | `gemini-3.5-flash,gemini-3.1-flash-lite` |
| `RECIPE_GEMINI_TIMEOUT_SECONDS` | Per-call timeout | `25` |
| `RECIPE_AGENT_DEADLINE_SECONDS` | Overall Gemini deadline per request | `90` |
| `GROQ_API_KEY` | Groq key for the recipe fallback | empty; fallback skipped |
| `GROQ_MODEL` | Groq model | `openai/gpt-oss-20b` |
| `RECIPE_AGENT_TOKEN` | Shared secret the app sends as `X-App-Token` | empty; API open (local dev only) |
| `RECIPE_AGENT_HOST` / `RECIPE_AGENT_PORT` | Local bind address | `127.0.0.1` / `8001` |

Build the app against the hosted backend with:

```powershell
flutter build apk --release --target-platform android-arm64 `
  --dart-define=RECIPE_AGENT_URL=https://<your-service>.onrender.com `
  --dart-define=RECIPE_AGENT_TOKEN=<same token as Render> `
  --dart-define=OCR_BACKEND_URL=http://127.0.0.1:8000
```

## Running the recipe backend

From the project directory:

```powershell
Set-Location 'D:\Semester-07\CapStone\Smart_Pantry_AI\Smart_Pantry_AI'
& 'D:\Semester-07\CapStone\Smart_Pantry_AI\.venv-kerasocr-tf210\Scripts\python.exe' -m recipe_agent.app
```

Verify only the local health endpoint:

```powershell
& curl.exe --noproxy '*' --max-time 10 -sS http://127.0.0.1:8001/health
```

For a physical Android device using `127.0.0.1`, configure ADB reverse
(`8000` for the OCR backend, `8001` for a local recipe backend):

```powershell
adb reverse tcp:8000 tcp:8000
adb reverse tcp:8001 tcp:8001
```

## Tests

```powershell
& 'D:\Semester-07\CapStone\Smart_Pantry_AI\.venv-kerasocr-tf210\Scripts\python.exe' -m pytest recipe_agent
flutter test
```

## Open in Android Studio
1. Extract this ZIP.
2. Open Android Studio.
3. Choose **Open**.
4. Select the extracted `Smart_Pantry_AI` folder.
5. Wait for Flutter/Gradle indexing to finish.
6. Run the app on an emulator or connected Android device.
