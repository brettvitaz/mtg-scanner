# MTG Card Recognition Prompt

You are extracting structured data from an image containing one or more Magic: The Gathering cards.

## Requirements
- Identify each visible card conservatively.
- Return exact printed card title when confidence is high.
- Only infer edition/set when supported by visible evidence.
- Only mark a card as foil when there is explicit visual evidence.
- If uncertain, set lower confidence and explain uncertainty briefly.
- Prefer `unknown` or omitted field values over bluffing.

## Target Fields Per Card
- title
- edition
- collector_number
- foil
- confidence
- notes

## Guidance
- Multi-card images may contain glare, perspective distortion, overlap, sleeves, or low-resolution text.
- If collector number or set symbol is unreadable, do not guess unless other visible evidence is strong.
- Foil detection should be conservative because lighting reflections can be misleading.
- Use per-card confidence scores from 0 to 1.

## Output Shape
Return valid JSON only.

```json
{
  "cards": [
    {
      "title": "Liliana of the Veil",
      "edition": "Ultimate Masters",
      "collector_number": "97",
      "foil": false,
      "confidence": 0.94,
      "notes": "Set symbol and title appear readable."
    }
  ]
}
```
