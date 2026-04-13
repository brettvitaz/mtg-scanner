# Request: Improve auto-scan accuracy

**Date:** [FILL: YYYY-MM-DD]
**Author:** [FILL: name or handle]

## Goal

Improve ios app auto-scan accuracy by limiting the detection window to the central section of the capture window. The detection currently identifies cards that are in places that are not expected from an auto-scan perspective, like near the extreme top, bottom, or sides. this leads to additional cards entering the recognition pipeline. in auto-scan mode there should only be one card identified. there is at least one consideration that must be planned for: different users will have different mounting solutions for the capture device (usually an iphone) and the detection window will need to be flexible in that regard.

The general rules are that:

- the object to be detected will generally be the largest card like item in the field of view
- the object to be detected will generally be near the center of the field of view, but keep in mind the device and mounting consideration

There is a capture trigger that gives the object some time to settle prior to image capture. The trigger gets activated when a card enters the field of view. This trigger area should be limited to the area that covers the detection window.

## Requirements

1. [FILL: first requirement]
2. [FILL: second requirement]
3. [FILL: add more as needed]

## Scope

**In scope:**
- [FILL: what this effort covers]

**Out of scope:**
- [FILL: what this effort does NOT cover]

## Verification

[FILL: how to confirm the work is correct — tests, commands, manual checks]

## Context

Files or docs the agent should read before starting:

- [FILL: path/to/relevant/file]
- [FILL: path/to/another/file]

## Notes

[FILL: anything else — constraints, preferences, prior art, links. Delete this section if empty.]
