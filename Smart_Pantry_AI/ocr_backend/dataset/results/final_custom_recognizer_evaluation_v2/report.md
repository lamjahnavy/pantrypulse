# Final Held-Out Custom Recognizer Evaluation

Dataset: `Products-Real/evaluation`.
Evaluation uses ground-truth expiry/component crops for both recognizers; detector performance is not measured.
Normalization trims and collapses whitespace only. WER is edit distance over whitespace-token strings.
No evaluation record was used for training, tuning, or model selection.

## Results

| Engine | Valid | CER | WER | Exact accuracy | Failures |
|---|---:|---:|---:|---:|---:|
| Trained custom recognizer | 664 | 0.055240 | 0.285643 | 0.743976 | 1 |
| Pretrained recognizer | 664 | 0.602493 | 1.000000 | 0.000000 | 2 |

## Component exact accuracy

### trained_custom_recognizer
- day: 0.9174603174603174 (630 records)
- month: 0.875 (664 records)
- year: 0.9145038167938931 (655 records)
### pretrained_recognizer_same_crops
- day: 0.4888888888888889 (630 records)
- month: 0.4683734939759036 (664 records)
- year: 0.4763358778625954 (655 records)

Valid records: 664 / 665.
Inference failures: 1.
Runtime seconds: 935.331.
