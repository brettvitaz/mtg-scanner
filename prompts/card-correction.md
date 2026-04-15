# MTG Card Correction Prompt

You are correcting a Magic: The Gathering card identification that could not be validated against the card database.

## Original Recognition (could not be validated)

- **Title**: {{title}}
- **Edition**: {{edition}}
- **Collector Number**: {{collector_number}}
- **Foil**: {{foil}}
- **Rejection reason**: {{reason}}

## Valid Printings

The card named "{{title}}" exists in the following confirmed printings. Select the one that best matches the card in the image based on set symbol, collector number, frame style, and any other visible details.

{{candidates_table}}

## Requirements

- You MUST select from the printings listed above. Do not invent a set or collector number that does not appear in the table.
- Use visible evidence: set symbol shape/color, collector number text, card frame, border style.
- If foil status is visible, only select a printing that supports it (check the finishes column).
- If you cannot determine which printing is correct, select the most recent printing and set confidence below 0.5.
- Return the same JSON format as a standard recognition.

## Output Shape

Return valid JSON only.

```json
{
  "cards": [
    {
      "title": "Pactdoll Terror",
      "edition": "Aetherdrift",
      "edition_notes": "AET set symbol visible; corrected from Dominaria which does not contain this card.",
      "collector_number": "99",
      "foil": false,
      "foil_type": "none",
      "foil_evidence": ["bullet separator visible — non-foil confirmed"],
      "list_reprint": "no",
      "list_symbol_visible": false,
      "border_color": "black",
      "copyright_line": "99 R\nAET • EN   John Avon",
      "promo_text": null,
      "confidence": 0.82,
      "notes": "Corrected: matched Aetherdrift set symbol; original set Dominaria was invalid for this card."
    }
  ]
}
```
