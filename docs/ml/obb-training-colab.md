# OBB Training In Colab

This app currently bundles `apps/ios/MTGScanner/Support/MTGCardDetector.mlpackage`, and the
compiled Core ML metadata shows it is a plain detection export:

- task: `detect`
- output tensor: `var_909`
- output shape: `1 x 5 x 8400`

That means there is no segmentation mask or polygon output available in the app today.

## Recommended Next Models

1. Train an oriented bounding box model for scan-time validation.
2. Optionally train an instance-segmentation model if you want polygon or mask output.

OBB is the cleaner fit if the goal is "one card, one angled rectangle" and the primary failure
mode is merged or poorly aligned axis-aligned boxes.

## Roboflow Project Setup

For OBB training, the dataset needs oriented box annotations rather than plain axis-aligned boxes.

Suggested project choices:

- one class: `card`
- annotation type: oriented bounding boxes
- include examples with:
  - side-by-side cards
  - stacked / slightly overlapping cards
  - cards near frame edges
  - perspective distortion
  - backgrounds that previously caused nested detections

Keep train / valid / test splits fixed once you have a representative dataset.

## Colab Outline

Use a GPU runtime and train with Ultralytics YOLO OBB.

```python
!pip install -U ultralytics roboflow
```

```python
from roboflow import Roboflow

rf = Roboflow(api_key="YOUR_API_KEY")
project = rf.workspace("YOUR_WORKSPACE").project("YOUR_PROJECT")
version = project.version(YOUR_VERSION)
dataset = version.download("yolov8-obb")
```

```python
from ultralytics import YOLO

model = YOLO("yolov8n-obb.pt")
results = model.train(
    data=f"{dataset.location}/data.yaml",
    epochs=100,
    imgsz=640,
    batch=16,
    degrees=0,
    perspective=0.0005,
    fliplr=0.0,
    mosaic=0.0,
    mixup=0.0,
    name="mtg-card-obb"
)
```

Those augmentation choices are intentionally conservative. For scan mode, preserving card geometry is
more important than aggressive augmentation.

## Export

Export the best weights to Core ML after training:

```python
best = YOLO("runs/obb/mtg-card-obb/weights/best.pt")
best.export(format="coreml", nms=False)
```

If you train segmentation instead, use the segmentation checkpoint family and export that model as
Core ML as well.

## Evaluation Checklist

Before replacing the bundled model, evaluate on difficult frames:

- two or three cards in a vertical column
- one card directly above another
- multiple cards with small spacing
- slightly tilted cards
- cards partially near the scan guide edges
- scenes that previously produced aggregate tall boxes

Prioritize:

- per-card stability across adjacent frames
- no merged detections
- no inner-feature detections chosen over full-card detections
- low false negatives on well-placed cards

## Integration Notes

If you ship an OBB model:

- the detector wrapper should decode oriented boxes instead of horizontal boxes
- scan validation should compare the oriented quadrilateral to the Vision rectangle corners
- containment suppression should prefer the larger supported quad, not raw axis-aligned overlap

If you ship a segmentation model:

- decode polygon or mask output
- treat that output as a soft anti-nesting signal
- avoid converting it back to a coarse axis-aligned box before validation
