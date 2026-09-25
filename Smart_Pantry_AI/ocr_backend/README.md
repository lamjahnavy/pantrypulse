# Pantry Pulse Keras-OCR Backend

This is the Phase 1 OCR backend skeleton. It exposes a small HTTP API around
the pretrained Keras-OCR pipeline. It is not trained or customized for Indian
FMCG packaging yet.

## Requirements

- Python 3.12
- A network connection the first time Keras-OCR downloads pretrained weights

Python 3.12 is used because it is installed in the project environment and has
compatible TensorFlow wheels. The backend is intentionally separate from the
Flutter application; Flutter is not connected to it in Phase 1.

## Install

From the repository root (`D:\Semester-07\CapStone\Smart_Pantry_AI`):

```powershell
Push-Location Smart_Pantry_AI
py -3.12 -m venv .venv-ocr
.\.venv-ocr\Scripts\Activate.ps1
python -m pip install --upgrade pip
python -m pip install -r ocr_backend\requirements.txt
```

## Start the backend

With `Smart_Pantry_AI` as the current directory and the virtual environment activated:

```powershell
python -m ocr_backend.app
```

From the repository root, the equivalent command is:

```powershell
Push-Location Smart_Pantry_AI
\.venv-ocr\Scripts\python.exe -m ocr_backend.app
```

The API listens on port `8000` on all interfaces. Use:

The first startup may take time while TensorFlow/Keras-OCR loads its pretrained
weights. Wait until Flask prints `Running on ...:8000` before opening the
scanner; captures after that use the already-loaded pipeline.

- Android emulator: `http://10.0.2.2:8000`
- Physical Android device: `http://YOUR_DEVELOPMENT_PC_LAN_IP:8000`

The Flutter client reads `OCR_BACKEND_URL` from a Dart define. For an emulator:

```powershell
flutter run --dart-define=OCR_BACKEND_URL=http://10.0.2.2:8000
```

For a physical device, replace the host with the development PC's LAN address
and ensure the device and PC are on the same network.

## Test the backend

Run the mocked HTTP-boundary tests without loading Keras-OCR weights:

```powershell
python -m pytest ocr_backend\test_app.py -q
```

Check the health endpoint:

```powershell
Invoke-RestMethod http://10.180.137.151:8000/health
```

## OCR request

Send a multipart upload using the `image` field:

```powershell
curl.exe -X POST http://127.0.0.1:8000/ocr -F "image=@C:\path\to\product.jpg"
```

The endpoint accepts images up to 10 MB. It returns raw recognized text and
the polygon associated with every Keras-OCR detection.

For a back-label retry focused on small MFD/EXP text, the same endpoint accepts
the optional multipart field `mode=date`:

```powershell
curl.exe -X POST http://10.180.142.87:8000/ocr `
  -F "mode=date" `
  -F "image=@C:\path\to\back-roi.jpg"
```

Date mode locates nearby date-label detections when available, then runs three
targeted image variants: upscaled color, upscaled contrast/sharpened grayscale,
and adaptive-threshold grayscale. It is used by Flutter only when normal back
OCR leaves MFD or expiry undetected.

Example response shape:

```json
{
  "engine": "keras_ocr",
  "text": "AMUL MILK",
  "detections": [
    {
      "text": "AMUL",
      "box": [[12.0, 20.0], [80.0, 20.0], [80.0, 45.0], [12.0, 45.0]]
    }
  ]
}
```

The exact text and boxes depend on the uploaded image. The backend does not
return field-level product parsing, confidence scoring, or Flutter model data
in this phase.

## Error responses

- `400`: missing or unreadable image
- `413`: image larger than 10 MB
- `415`: non-image content type
- `502`: Keras-OCR inference failure

## Phase 1 limitation

The backend uses the pretrained Keras-OCR model only. No Indian FMCG dataset,
fine-tuning, domain vocabulary, preprocessing experiments, evaluation results,
or Flutter integration are included yet.

## Phase 2 evaluation

The real-image baseline manifest is in `dataset/manifest.json`. It contains
front and back/side package views with manually recorded visible text and
source provenance. Run the pretrained baseline evaluator from the project
directory with the OCR environment activated:

```powershell
$env:PYTHONPATH = (Join-Path $PWD 'Smart_Pantry_AI')
python Smart_Pantry_AI\ocr_backend\evaluate.py
```

The evaluator saves raw detections and summary metrics to
`dataset/results/keras_ocr_baseline.json`. Phase 3 saves its report to
`dataset/results/keras_ocr_preprocessing_results.json`. It resizes only the
in-memory evaluation copies to bounded dimensions to keep CPU evaluation
tractable; original image files remain unchanged.