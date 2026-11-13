# Expiry-Crop Preprocessing Experiment

Engine: existing pretrained Keras-OCR pipeline; no training or fine-tuning.
Ground truth: Products-Real/evaluation `exp` transcription and bounding box.
Each crop was created in memory; source images were not modified.
Normalization: trim and collapse whitespace only.

## A. Baseline result

The baseline variant is `original_crop`; this is a crop-only comparison and is not the full-image external baseline.

## B. Preprocessing variants tested

- `original_crop`
- `upscaled_crop`
- `grayscale_contrast`
- `adaptive_threshold`
- `upscaled_contrast`
- `upscaled_adaptive`
- `upscaled_sharpened_contrast`

## C. Metrics

| Variant | Processed | Correct | Failed | Exact accuracy | Mean CER |
|---|---:|---:|---:|---:|---:|
| original_crop | 50 | 0 | 50 | 0.000000 | 0.564214 |
| upscaled_crop | 50 | 0 | 50 | 0.000000 | 0.733500 |
| grayscale_contrast | 50 | 0 | 50 | 0.000000 | 0.639500 |
| adaptive_threshold | 50 | 0 | 50 | 0.000000 | 0.684000 |
| upscaled_contrast | 50 | 0 | 50 | 0.000000 | 0.750071 |
| upscaled_adaptive | 50 | 0 | 50 | 0.000000 | 0.845714 |
| upscaled_sharpened_contrast | 50 | 0 | 50 | 0.000000 | 0.743571 |

## D. Best-performing variant

`original_crop` ranked by exact normalized accuracy, then mean CER.

## E. Representative before/after examples

- `test_00001.jpg` — ground truth: `2021.08.03`
  - `original_crop`: `z0z1 os os` (CER 0.8000, exact=False)
  - `upscaled_crop`: `zoz ok l os` (CER 1.1000, exact=False)
  - `grayscale_contrast`: `21z1 os ca` (CER 0.8000, exact=False)
  - `adaptive_threshold`: `zozl isk` (CER 1.0000, exact=False)
  - `upscaled_contrast`: `uz1 os lak` (CER 1.0000, exact=False)
  - `upscaled_adaptive`: `ssls si es ee` (CER 1.3000, exact=False)
  - `upscaled_sharpened_contrast`: `vuz1 as lx` (CER 0.9000, exact=False)
- `test_00002.jpg` — ground truth: `11/11/21`
  - `original_crop`: `lllls` (CER 1.0000, exact=False)
  - `upscaled_crop`: `ed` (CER 1.0000, exact=False)
  - `grayscale_contrast`: `l` (CER 1.0000, exact=False)
  - `adaptive_threshold`: `e iri` (CER 1.0000, exact=False)
  - `upscaled_contrast`: `s s` (CER 1.0000, exact=False)
  - `upscaled_adaptive`: `` (CER 1.0000, exact=False)
  - `upscaled_sharpened_contrast`: `s s` (CER 1.0000, exact=False)
- `test_00003.jpg` — ground truth: `2021.01.16`
  - `original_crop`: `mozio1 1e` (CER 0.8000, exact=False)
  - `upscaled_crop`: `fes s 1e d 1n 1 ese l d` (CER 2.0000, exact=False)
  - `grayscale_contrast`: `osindi 1t` (CER 0.9000, exact=False)
  - `adaptive_threshold`: `enalfite` (CER 1.0000, exact=False)
  - `upscaled_contrast`: `1 1 cln rnos e` (CER 1.4000, exact=False)
  - `upscaled_adaptive`: `lere 1x 1 4` (CER 1.0000, exact=False)
  - `upscaled_sharpened_contrast`: `1 1 cln rns e` (CER 1.3000, exact=False)
- `test_00004.jpg` — ground truth: `2021.02.04`
  - `original_crop`: `202110204` (CER 0.2000, exact=False)
  - `upscaled_crop`: `202110204` (CER 0.2000, exact=False)
  - `grayscale_contrast`: `202110204` (CER 0.2000, exact=False)
  - `adaptive_threshold`: `20270204` (CER 0.3000, exact=False)
  - `upscaled_contrast`: `2021oz04` (CER 0.4000, exact=False)
  - `upscaled_adaptive`: `d oe dn` (CER 1.0000, exact=False)
  - `upscaled_sharpened_contrast`: `2o2to2 04` (CER 0.5000, exact=False)
- `test_00005.jpg` — ground truth: `2021.03.27`
  - `original_crop`: `20210327` (CER 0.2000, exact=False)
  - `upscaled_crop`: `20210327` (CER 0.2000, exact=False)
  - `grayscale_contrast`: `20210327` (CER 0.2000, exact=False)
  - `adaptive_threshold`: `20210327` (CER 0.2000, exact=False)
  - `upscaled_contrast`: `20210827` (CER 0.3000, exact=False)
  - `upscaled_adaptive`: `tas oasotn` (CER 1.0000, exact=False)
  - `upscaled_sharpened_contrast`: `20210327` (CER 0.2000, exact=False)
- `test_00006.jpg` — ground truth: `2021.06.09`
  - `original_crop`: `foei q6 qs` (CER 0.9000, exact=False)
  - `upscaled_crop`: `i` (CER 1.0000, exact=False)
  - `grayscale_contrast`: `poet ue qs` (CER 1.0000, exact=False)
  - `adaptive_threshold`: `oredg ruzin` (CER 1.1000, exact=False)
  - `upscaled_contrast`: `` (CER 1.0000, exact=False)
  - `upscaled_adaptive`: `` (CER 1.0000, exact=False)
  - `upscaled_sharpened_contrast`: `` (CER 1.0000, exact=False)
- `test_00007.jpg` — ground truth: `2021.08.14`
  - `original_crop`: `08 22 a` (CER 0.9000, exact=False)
  - `upscaled_crop`: `14 221 0` (CER 0.9000, exact=False)
  - `grayscale_contrast`: `06 202 f` (CER 0.8000, exact=False)
  - `adaptive_threshold`: `m1 0 1` (CER 0.7000, exact=False)
  - `upscaled_contrast`: `zzo s` (CER 1.0000, exact=False)
  - `upscaled_adaptive`: `dmlla` (CER 1.0000, exact=False)
  - `upscaled_sharpened_contrast`: `zo l` (CER 1.0000, exact=False)
- `test_00008.jpg` — ground truth: `21.12.22`
  - `original_crop`: `t100` (CER 0.8750, exact=False)
  - `upscaled_crop`: `` (CER 1.0000, exact=False)
  - `grayscale_contrast`: `7120` (CER 0.7500, exact=False)
  - `adaptive_threshold`: `on` (CER 1.0000, exact=False)
  - `upscaled_contrast`: `` (CER 1.0000, exact=False)
  - `upscaled_adaptive`: `` (CER 1.0000, exact=False)
  - `upscaled_sharpened_contrast`: `` (CER 1.0000, exact=False)
- `test_00009.jpg` — ground truth: `02.2023`
  - `original_crop`: `022023` (CER 0.1429, exact=False)
  - `upscaled_crop`: `2023 02` (CER 0.5714, exact=False)
  - `grayscale_contrast`: `oz 2023` (CER 0.4286, exact=False)
  - `adaptive_threshold`: `0z2023` (CER 0.2857, exact=False)
  - `upscaled_contrast`: `2023 02 c` (CER 0.7143, exact=False)
  - `upscaled_adaptive`: `022023` (CER 0.1429, exact=False)
  - `upscaled_sharpened_contrast`: `2023 02 c` (CER 0.7143, exact=False)
- `test_00010.jpg` — ground truth: `15.09.2024`
  - `original_crop`: `1509 2024` (CER 0.2000, exact=False)
  - `upscaled_crop`: `15092024` (CER 0.2000, exact=False)
  - `grayscale_contrast`: `15092024` (CER 0.2000, exact=False)
  - `adaptive_threshold`: `15092024` (CER 0.2000, exact=False)
  - `upscaled_contrast`: `15409 2024` (CER 0.2000, exact=False)
  - `upscaled_adaptive`: `so2024` (CER 0.6000, exact=False)
  - `upscaled_sharpened_contrast`: `1509 2024` (CER 0.2000, exact=False)

## F. Whether preprocessing alone appears sufficient

This experiment measures crop-level recognition only. It cannot establish production sufficiency without comparing the best variant against the full-image baseline and testing runtime cost.

## G. Whether fine-tuning should be considered next

Fine-tuning should only be considered after reviewing these measured results and confirming that preprocessing alone does not meet the expiry-date requirement. No fine-tuning was performed.

## Failures

None.
