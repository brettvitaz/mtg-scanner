# Roboflow OBB Training From Scratch

This guide is for training a new MTG card oriented bounding box model when you:

- do not own the original Roboflow workspace
- do not have labeled images yet
- want to train in Google Colab
- eventually want a Core ML model for the iOS app

## Recommendation

Use your own new Roboflow workspace and create a new `Instance Segmentation` project as the
label source of truth.

Reason:

- you are starting from scratch anyway
- polygon labels are easier to create in Roboflow than OBB labels
- those polygon labels can be converted into OBB labels for Ultralytics training
- the same source labels can later support a segmentation model if needed

## Step 1: Create Your Roboflow Workspace

1. Log in to Roboflow.
2. In the left sidebar, click the workspace name.
3. Click `+`.
4. Create a new workspace under your own account.
5. Give it a clear name, for example `mtg-scanner`.

## Step 2: Create the Project

1. Inside your workspace, click `Create New Project`.
2. Set the project name to something like `mtg-card-obb-source`.
3. Choose project type `Instance Segmentation`.
4. Create one class only:

```text
card
```

Do not reuse the public project you linked earlier. Treat your project as a clean training source
for your own app.

## Step 3: Capture Images

You need your own dataset first.

Capture images from the same kinds of scan scenes the app will actually see:

- one well-centered card
- two side-by-side cards
- three cards in a column
- cards near frame edges
- cards with mild perspective distortion
- cards under mixed lighting
- failure cases where nested or aggregate boxes appear

Guidelines:

- start with 50 to 100 images for a first pass
- include both easy and hard scenes
- do not overfocus on perfect examples
- keep backgrounds realistic for your scanner use case

If you have video from the phone, you can extract frames and upload them too.

## Step 4: Upload Images

1. Open your Roboflow project.
2. Upload the images.
3. Wait for processing to finish.

If the dataset is still small, the web uploader is fine.

## Step 5: Annotate Cards As Polygons

Annotate each visible card with a polygon that follows the card edges.

Best practice for this use case:

- use `Smart Polygon` when it helps
- keep the polygon simple
- place points on the visible card corners and edges
- prefer a 4-corner outline when possible
- annotate partial cards only if you expect the app to detect partial cards

Do not trace art details or the interior of the card. The annotation should represent the card
boundary.

## Step 6: Review Label Quality

Before training, spot-check labels for:

- missed cards
- duplicate labels
- polygons that cut across the wrong object
- labels that include large background regions
- inconsistent corner placement between similar images

Bad labels will hurt OBB training more than a small dataset will.

## Step 7: Generate A Dataset Version

1. Go to `Versions`.
2. Generate version `1`.
3. Keep preprocessing and augmentation conservative for the first pass.

You can tune augmentations later after you have a baseline model.

## Step 8: Open Google Colab

Create a new Colab notebook and switch to a GPU runtime.

Recommended runtime setup:

1. `Runtime`
2. `Change runtime type`
3. Hardware accelerator: `GPU`

## Step 9: Install Dependencies

Run this in Colab:

```python
!pip install -U roboflow ultralytics opencv-python-headless pyyaml numpy
```

## Step 10: Download The Roboflow Dataset

Fill in your own values:

```python
from roboflow import Roboflow

ROBOFLOW_API_KEY = "YOUR_API_KEY"
WORKSPACE_ID = "your-workspace-id"
PROJECT_ID = "mtg-card-obb-source"
VERSION_NUMBER = 1

rf = Roboflow(api_key=ROBOFLOW_API_KEY)
project = rf.workspace(WORKSPACE_ID).project(PROJECT_ID)
version = project.version(VERSION_NUMBER)

dataset = version.download(model_format="coco-segmentation", location="/content/datasets")
print(dataset.location)
```

This downloads the labeled polygons in COCO segmentation format.

## Step 11: Convert Polygons To YOLO OBB Labels

Ultralytics OBB training expects each label row to look like:

```text
class_index x1 y1 x2 y2 x3 y3 x4 y4
```

with normalized coordinates.

Run this conversion script in Colab:

```python
from pathlib import Path
import json
import shutil
import cv2
import numpy as np
import yaml

ROOT = Path(dataset.location)
OUT = ROOT / "yolo_obb"

def order_points_clockwise(pts):
    pts = np.array(pts, dtype=np.float32)
    center = pts.mean(axis=0)
    angles = np.arctan2(pts[:, 1] - center[1], pts[:, 0] - center[0])
    pts = pts[np.argsort(angles)]
    start = np.argmin(pts.sum(axis=1))
    return np.roll(pts, -start, axis=0)

for split in ["train", "valid", "test"]:
    ann_path = ROOT / split / "_annotations.coco.json"
    if not ann_path.exists():
        continue

    with open(ann_path, "r") as f:
        coco = json.load(f)

    images_by_id = {img["id"]: img for img in coco["images"]}
    anns_by_image = {}
    for ann in coco["annotations"]:
        anns_by_image.setdefault(ann["image_id"], []).append(ann)

    (OUT / "images" / split).mkdir(parents=True, exist_ok=True)
    (OUT / "labels" / split).mkdir(parents=True, exist_ok=True)

    for image_id, image_info in images_by_id.items():
        src_img = ROOT / split / image_info["file_name"]
        dst_img = OUT / "images" / split / image_info["file_name"]
        if src_img.exists():
            shutil.copy2(src_img, dst_img)

        width = float(image_info["width"])
        height = float(image_info["height"])
        label_lines = []

        for ann in anns_by_image.get(image_id, []):
            segs = ann.get("segmentation", [])
            if not segs:
                continue

            for seg in segs:
                pts = np.array(seg, dtype=np.float32).reshape(-1, 2)
                if len(pts) < 4:
                    continue

                rect = cv2.minAreaRect(pts)
                box = cv2.boxPoints(rect)
                box = order_points_clockwise(box)

                box[:, 0] /= width
                box[:, 1] /= height
                box = np.clip(box, 0.0, 1.0)

                flat = " ".join(f"{v:.6f}" for v in box.reshape(-1))
                label_lines.append(f"0 {flat}")

        label_path = OUT / "labels" / split / f"{Path(image_info['file_name']).stem}.txt"
        with open(label_path, "w") as f:
            f.write("\n".join(label_lines))

data_yaml = {
    "path": str(OUT),
    "train": "images/train",
    "val": "images/valid",
    "test": "images/test",
    "names": {0: "card"},
}

with open(OUT / "data.yaml", "w") as f:
    yaml.safe_dump(data_yaml, f, sort_keys=False)

print("Wrote OBB dataset to", OUT)
```

## Step 12: Sanity-Check The Converted OBB Labels

Before training, visually verify the conversion on a few examples.

Run this in Colab:

```python
from pathlib import Path
import cv2
import matplotlib.pyplot as plt
import numpy as np

DATA_ROOT = Path("/content/datasets")
obb_root = next(DATA_ROOT.rglob("yolo_obb"))

sample_image = next((obb_root / "images" / "train").glob("*"))
label_file = obb_root / "labels" / "train" / f"{sample_image.stem}.txt"

image = cv2.cvtColor(cv2.imread(str(sample_image)), cv2.COLOR_BGR2RGB)
h, w = image.shape[:2]

if label_file.exists():
    for line in label_file.read_text().splitlines():
        parts = line.split()
        coords = np.array(list(map(float, parts[1:])), dtype=np.float32).reshape(4, 2)
        coords[:, 0] *= w
        coords[:, 1] *= h
        coords = coords.astype(np.int32)
        cv2.polylines(image, [coords], isClosed=True, color=(0, 255, 0), thickness=3)

plt.figure(figsize=(10, 10))
plt.imshow(image)
plt.axis("off")
plt.show()
```

If these overlays look wrong, do not train yet. Fix the conversion or labels first.

## Step 13: Train The OBB Model

Use a small model first.

```python
from ultralytics import YOLO

model = YOLO("yolo26n-obb.pt")
results = model.train(
    data=str(obb_root / "data.yaml"),
    epochs=100,
    imgsz=640,
    batch=16,
    name="mtg-card-obb"
)
```

If Colab memory is tight, lower the batch size to `8`.

## Step 14: Validate The Model

```python
best = YOLO("/content/runs/obb/mtg-card-obb/weights/best.pt")
metrics = best.val(data=str(obb_root / "data.yaml"))
print(metrics.box.map, metrics.box.map50)
```

Metrics are useful, but for this app the real test is whether individual cards remain separate and
stable in difficult scan scenes.

## Step 15: Export To Core ML

```python
best.export(format="coreml", imgsz=640, nms=False)
```

This should produce an `.mlpackage`.

## Step 16: Bring The Model Into The App

After export:

1. Download the `.mlpackage` from Colab.
2. Replace the bundled detector model in the iOS project.
3. Update the detector wrapper to decode OBB output instead of plain detection output.

Important:

- the current iOS detector code is written for a plain detect model
- an OBB model is not drop-in compatible with the existing decoder
- the app will need decoder changes before the new model can be used correctly

## Suggested First Dataset Scope

For your first training round:

- 75 to 150 images
- 1 class
- realistic scan scenes only
- careful labels

That is enough to learn whether OBB helps your scan pipeline before you invest in a larger dataset.

## What To Do Next After First Training

If the first OBB model looks promising:

1. collect more real failure cases from the app
2. add those images to Roboflow
3. fix or tighten labels
4. generate a new version
5. retrain
6. compare live stability frame-to-frame

If OBB still is not stable enough, train a true segmentation model from the same polygon labels and
integrate mask or polygon output instead of relying on axis-aligned YOLO boxes.
