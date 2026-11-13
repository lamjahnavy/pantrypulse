# External Keras-OCR Baseline Evaluation

Engine: pretrained Keras-OCR pipeline used by `ocr_backend.app.KerasOcrEngine`.
Detection matching: one-to-one greedy matching with IoU >= 0.5.
Unmatched ground-truth regions count as false negatives; unmatched predictions count as false positives.
Text normalization trims and collapses whitespace only. Raw values are preserved in predictions.jsonl.

## A. Dataset summary

| Dataset/field | Images | Ground-truth regions | Processed images | Failed images |
|---|---:|---:|---:|---:|
| date | 64 | 68 | 64 | 0 |
| day | 485 | 485 | 485 | 0 |
| expiry_date | 665 | 665 | 665 | 0 |
| month | 510 | 510 | 510 | 0 |
| year | 497 | 497 | 497 | 0 |

## B. Detection metrics

### date
- Precision: 0.005017
- Recall: 0.573529
- F1: 0.009946
- Matched regions: 39
- Unmatched ground truth: 29
- Unmatched predictions: 7735

### day
- Precision: 0.248062
- Recall: 0.527835
- F1: 0.337508
- Matched regions: 256
- Unmatched ground truth: 229
- Unmatched predictions: 776

### expiry_date
- Precision: 0.006247
- Recall: 0.600000
- F1: 0.012365
- Matched regions: 399
- Unmatched ground truth: 266
- Unmatched predictions: 63472

### month
- Precision: 0.206349
- Recall: 0.433333
- F1: 0.279570
- Matched regions: 221
- Unmatched ground truth: 289
- Unmatched predictions: 850

### year
- Precision: 0.245229
- Recall: 0.517103
- F1: 0.332686
- Matched regions: 257
- Unmatched ground truth: 240
- Unmatched predictions: 791

## C. OCR metrics

### date
- Mean CER: 0.708757
- Exact normalized text accuracy: 0.000000

### day
- Mean CER: 0.687629
- Exact normalized text accuracy: 0.280412

### expiry_date
- Mean CER: 0.732532
- Exact normalized text accuracy: 0.000000

### month
- Mean CER: 0.800980
- Exact normalized text accuracy: 0.201961

### year
- Mean CER: 0.693159
- Exact normalized text accuracy: 0.265594

## D. Expiry metrics

- Complete expiry-date accuracy: 0.000000
- Day accuracy: 0.0
- Month accuracy: 0.0
- Year accuracy: 0.0

## E. Error examples

- `test_00006.jpg` (date): missed detection
  - Ground truth: `2020.12.10`
  - Prediction: ``
  - Ground-truth box: `(366.0, 871.0, 580.0, 906.0)`
  - Prediction box: `None`
- `test_00018.jpg` (date): missed detection
  - Ground truth: `18/11/2019`
  - Prediction: ``
  - Ground-truth box: `(441.0, 411.0, 589.0, 454.0)`
  - Prediction box: `None`
- `test_00021.jpg` (date): partial date
  - Ground truth: `21.03.12`
  - Prediction: `2106412`
  - Ground-truth box: `(381.0, 606.0, 500.0, 639.0)`
  - Prediction box: `(378.1527404785156, 604.5636596679688, 505.8023986816406, 644.5743408203125)`
- `test_00022.jpg` (date): partial date
  - Ground truth: `2021.03.12`
  - Prediction: `20210312`
  - Ground-truth box: `(934.0, 646.0, 1080.0, 671.0)`
  - Prediction box: `(931.39794921875, 646.4848022460938, 1082.65087890625, 675.3699951171875)`
- `test_00023.jpg` (date): partial date
  - Ground truth: `21.03.10`
  - Prediction: `20310`
  - Ground-truth box: `(1092.0, 682.0, 1338.0, 748.0)`
  - Prediction box: `(1088.0, 680.0, 1344.0, 752.0)`
- `test_00037.jpg` (date): partial date
  - Ground truth: `10.08.2020`
  - Prediction: `10081`
  - Ground-truth box: `(441.0, 908.0, 588.0, 938.0)`
  - Prediction box: `(441.169921875, 906.611328125, 526.833984375, 938.021484375)`
- `test_00088.jpg` (date): partial date
  - Ground truth: `2021.01.08`
  - Prediction: `20210108`
  - Ground-truth box: `(441.0, 360.0, 636.0, 398.0)`
  - Prediction box: `(439.0178527832031, 357.8504638671875, 641.1242065429688, 403.81634521484375)`
- `test_00102.jpg` (date): missed detection
  - Ground truth: `2020.10.15`
  - Prediction: ``
  - Ground-truth box: `(434.0, 896.0, 615.0, 925.0)`
  - Prediction box: `None`
- `test_00115.jpg` (date): partial date
  - Ground truth: `13.11.2020`
  - Prediction: `13112020`
  - Ground-truth box: `(645.0, 775.0, 938.0, 818.0)`
  - Prediction box: `(644.0, 774.0, 942.0, 822.0)`
- `test_00143.jpg` (date): partial date
  - Ground truth: `2020-12-08`
  - Prediction: `2020112408`
  - Ground-truth box: `(612.0, 245.0, 918.0, 289.0)`
  - Prediction box: `(612.0, 242.0, 920.0, 292.0)`
- `test_00148.jpg` (date): partial date
  - Ground truth: `2021-01-11`
  - Prediction: `202110111`
  - Ground-truth box: `(384.0, 715.0, 513.0, 736.0)`
  - Prediction box: `(383.8593444824219, 713.1557006835938, 517.515869140625, 739.606201171875)`
- `test_00149.jpg` (date): partial date
  - Ground truth: `2020-08-18`
  - Prediction: `202010818`
  - Ground-truth box: `(376.0, 1026.0, 563.0, 1057.0)`
  - Prediction box: `(375.5029296875, 1024.4853515625, 566.796875, 1061.3271484375)`
- `test_00165.jpg` (date): partial date
  - Ground truth: `11.09.2020`
  - Prediction: `1092020`
  - Ground-truth box: `(308.0, 958.0, 477.0, 987.0)`
  - Prediction box: `(319.678955078125, 956.4364013671875, 480.00927734375, 988.9041748046875)`
- `test_00187.jpg` (date): missed detection
  - Ground truth: `20.11.2019`
  - Prediction: ``
  - Ground-truth box: `(363.0, 753.0, 466.0, 787.0)`
  - Prediction box: `None`
- `test_00213.jpg` (date): partial date
  - Ground truth: `27/09/2020`
  - Prediction: `mfg2710912020`
  - Ground-truth box: `(242.0, 880.0, 419.0, 914.0)`
  - Prediction box: `(179.3302459716797, 876.1344604492188, 421.506103515625, 923.38671875)`
- `test_00218.jpg` (date): partial date
  - Ground truth: `10.02.20`
  - Prediction: `10012d`
  - Ground-truth box: `(472.0, 458.0, 585.0, 491.0)`
  - Prediction box: `(469.798828125, 456.6826171875, 587.8447265625, 492.4541015625)`
- `test_00225.jpg` (date): incorrect character
  - Ground truth: `21/11/2020`
  - Prediction: `stiszoen`
  - Ground-truth box: `(736.0, 444.0, 915.0, 470.0)`
  - Prediction box: `(771.875, 444.3359375, 916.6015625, 470.99609375)`
- `test_00226.jpg` (date): missed detection
  - Ground truth: `2020.11.07`
  - Prediction: ``
  - Ground-truth box: `(587.0, 891.0, 722.0, 917.0)`
  - Prediction box: `None`
- `test_00233.jpg` (date): partial date
  - Ground truth: `2020/06/01`
  - Prediction: `2o2ovofiot`
  - Ground-truth box: `(615.0, 330.0, 749.0, 353.0)`
  - Prediction box: `(612.6943359375, 328.4423828125, 750.04296875, 354.7177734375)`
- `test_00234.jpg` (date): incorrect character
  - Ground truth: `2021.02.06`
  - Prediction: `eoeae`
  - Ground-truth box: `(624.0, 118.0, 765.0, 136.0)`
  - Prediction box: `(623.0, 117.0, 732.0, 137.0)`

## Runtime failures

None.
