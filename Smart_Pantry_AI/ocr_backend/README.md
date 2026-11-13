# Pantry Pulse Keras-OCR Backend

This is the Keras-OCR backend for product scanning. Flutter sends both front
and back product captures to this API; there is no on-device ML Kit OCR path.
The backend uses the pretrained Keras-OCR pipeline. It is not trained or
customized for Indian FMCG packaging.

The pretrained and exported custom date recognizers are loaded once at backend
startup. Normal scans use the pretrained recognizer. By default,
`OCR_DATE_RETRY_MODE=custom_lightweight` reuses the normal detector boxes,
selects at most 15 date-like candidates, and recognizes each candidate with the
custom recognizer using the original crop and at most one upscale. Set
`OCR_DATE_RETRY_MODE=pretrained_fallback` to retain the older pretrained-only
date retry path. `OCR_RECOGNIZER_MODE` remains `pretrained` by default and
controls the health/status mode and legacy fallback behavior.

For evidence collection, set `OCR_DEBUG=1` and `OCR_DEBUG_DIR` to a writable
directory. The date retry then saves each selected crop and its upscaled
variant, and the response includes candidate bounds, crop sizes, variant text,
scores, and clipping flags. Debug logging is disabled by default.

The following opt-in settings are used for controlled crop experiments:

- `OCR_DATE_CROP_PADDING`: fractional padding around each candidate, for
  example `0.15`; default `0`.
- `OCR_DATE_UPSCALE_MODE`: `cubic` or `lanczos`; default `cubic`.
- `OCR_DATE_UPSCALE_SCALE`: maximum upscale factor; default `2`.
- `OCR_DATE_CANDIDATE_LIMIT`: number of date-retry crops, capped at 15; default `8`.
- `OCR_DATE_VARIANT_LIMIT`: `1`, `2`, or `3`; default `2`. A second variant is skipped when the first returns a valid calendar date.
- `OCR_DETECTOR_LONG_SIDE`: detector working-copy long side, clamped to
  `640`-`2400`; default `1600`.
- `OCR_SERIALIZE_REQUESTS`: set to `1` to serialize OCR inference requests.
  It defaults to `0`; CPU overlap testing showed no end-to-end benefit from
  serialization.

The resumable phone evaluator writes parser output, SHA-256 hashes, distinct
image counts, exact-match metrics, and digit-level metrics into its JSON
output. Identical files are processed once. Keep fixed development photos
separate from new-pack test photos; do not tune settings on the test set.

## Requirements

- Python 3.12
- A network connection the first time Keras-OCR downloads pretrained weights

Python 3.12 is used because it is installed in the project environment and has
compatible TensorFlow wheels. The backend runs as a separate HTTP process that
the Flutter scanner connects to.

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

To select the explicit pretrained-only fallback before starting Flask:

```powershell
$env:OCR_DATE_RETRY_MODE = "pretrained_fallback"
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

Date mode reuses the normal pass detections and does not run the detector again.
It selects at most 15 boxes near date labels, date-like digit text, or the lower
label area. Each selected crop is recognized in its original form and, when
small, once after upscaling.

For opt-in diagnostics, set `OCR_DEBUG=true` to log ordered detections and
grouped reading-order lines. To additionally save the decoded input and date
variants, set `OCR_DEBUG_DIR` to an explicitly chosen local directory. These
options are disabled by default because OCR text and package images may be
sensitive.

Example response shape:

```json
{
  "engine": "keras_ocr",
  "status": "ok",
  "text": "AMUL MILK",
  "detections": [
    {
      "text": "AMUL",
      "box": [[12.0, 20.0], [80.0, 20.0], [80.0, 45.0], [12.0, 45.0]]
    }
  ],
  "lines": [
    {
      "text": "AMUL",
      "detections": [
        {
          "text": "AMUL",
          "box": [[12.0, 20.0], [80.0, 20.0], [80.0, 45.0], [12.0, 45.0]]
        }
      ]
    }
  ],
  "processing_ms": 123.4,
  "error_code": null
}
```

When Keras-OCR finds no usable text, the response is successful but explicit:

```json
{
  "engine": "keras_ocr",
  "status": "empty",
  "text": "",
  "detections": [],
  "lines": [],
  "processing_ms": 123.4,
  "error_code": "EMPTY_OCR"
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

The Flutter scanner treats network failures, timeouts, malformed responses and
empty OCR results as retryable conditions while preserving the existing
front/back capture and review/edit flow.

## Lightweight date retry limitation

The custom recognizer does not replace normal product OCR and its saved
74.3976% result is recognition-only accuracy on held-out ground-truth crops.
It is not a phone or full-image end-to-end accuracy claim. The lightweight
retry annotates generated detections with `recognizer: "custom_date"` while
normal detections are annotated `recognizer: "pretrained"`.

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

### External dataset baseline evaluation

The standalone external evaluator reads the original annotation files from
`Smart_Pantry_Datasets/Date-Real` and
`Smart_Pantry_Datasets/Products-Real/evaluation`. It uses the same pretrained
`KerasOcrEngine` as the Flask API, does not modify the source datasets, and
does not train or fine-tune a model:

```powershell
Push-Location Smart_Pantry_AI
$env:PYTHONPATH = $PWD
python ocr_backend\evaluate_external_datasets.py
Pop-Location
```

Results are written only to:

```text
ocr_backend/dataset/results/external/
├── predictions.jsonl
├── summary.json
└── report.md
```

Detections are matched one-to-one using IoU >= 0.5. Unmatched ground-truth
regions count as false negatives, unmatched predictions count as false
positives, and recognition normalization trims/collapses whitespace only.
Raw OCR text and polygons remain in `predictions.jsonl`. The evaluation
includes Date-Real day/month/year and Products-Real evaluation `exp` and
generic `date`; it does not claim MFD, product-name, quantity, or price
accuracy where the datasets provide no such ground truth.