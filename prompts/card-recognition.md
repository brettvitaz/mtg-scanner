# MTG Card Recognition Prompt v2

You are extracting structured data from an image containing one or more Magic: The Gathering cards.

## Core Requirements

- Identify each visible card conservatively.
- Return the exact printed card title when confidence is high.
- Only infer edition/set when supported by visible evidence — follow the identification steps below in order.
- If uncertain, set a lower confidence score and explain briefly in `notes`.
- Prefer `unknown` or omitted field values over guessing.
- Never conflate a dark card frame interior with a black card border — see Border Color below.

---

## Step 1: Read the Bottom Info Line

Before doing anything else, examine the bottom strip of the card carefully. Different eras have different formats:

### Modern format (M15 / 2014 and later)
The bottom-left contains a stacked two-line block:
```
[collector number] [rarity letter]
[SET CODE] [separator] [LANG]   [artist credit]
```
- The **separator** between SET CODE and LANG is either:
  - A bullet point `•` → **non-foil**
  - A star `★` → **foil (premium)**
- Transcribe this separator character exactly. It is the most reliable foil indicator when legible.
- A holofoil oval security stamp on the power/toughness box is present on ALL rares and mythics from this era regardless of foil status. It is NOT a foil indicator.
- **Set code**: The three-letter code (e.g., WAR, M10, 40K) appears after the separator. Output ONLY this code for the "edition" field, not the full set name.
- **Collector number**: extract ONLY the numeric portion (and any suffix like 'e' for etched or '★' for promos). Do NOT include the rarity letter (C, U, R, M) or the total card count. Examples: "166" from "166 C", "145" from "145/264 C", "050e" from "050e".

### Pre-M15 format (pre-2014, post-Exodus)
Format varies but typically:
```
[SET SYMBOL visible mid-right on card]
[collector number] / [set total]   [artist credit]   TM & © [year] Wizards of the Coast
```
- No SET CODE or LANG text line. No separator character to read.
- Foil must be determined from visual evidence only (see Foil Detection below).

### Pre-Exodus format (Alpha through Exodus, 1993–1998)
No collector number. No set symbol on Alpha/Beta/Unlimited/Revised/4th/5th Edition.
Bottom line format:
```
Illus. [©] [Artist Name]          [optional: © [year] Wizards of the Coast]
```
- The presence or absence of `©` before the artist name, and the copyright year, are the primary set discriminators — see Early Set Identification below.
- Transcribe the full bottom credit line verbatim. This is the most important data point for early cards.

---

## Step 2: Read the Border Color

The card **border** is the solid-colored outermost edge of the physical card, outside all frame elements.

- **White or cream outer edge** → white border
- **True black outer edge** → black border

⚠️ Do NOT infer border color from the card frame interior. Early cards (Alpha through 4th Edition) have very dark textured frame interiors (stone, metal, leather) that can appear black. Always look at the outermost physical edge. If the card is in a sleeve or the edges are not visible, report border color as `unknown`.

**Known border colors by set** (use these when the physical edge is ambiguous or hidden):
| Sets | Border |
|---|---|
| Alpha, Beta | Black |
| Unlimited Edition | White |
| Revised Edition (3rd Edition) | White |
| 4th Edition, 5th Edition | White |
| 6th Edition (Classic Core Set) and later core sets through 7th Edition | White |
| 8th Edition and later | Black |
| Foreign Black Border (FBB) editions | Black |
| International Collector's Edition | Black |
| Collector's Edition (CE/IE) | Black |

For modern sets (M15 era and later), border color is almost always black unless it's a specialty product.

---

## Step 3: Identify the Printing Variant

### The List / Mystery Booster Symbol (Planeswalker Icon)
If a second image (close-up of the bottom-left corner) is provided alongside the full card image, **use the close-up for:**
1. **List/Mystery Booster determination** — the Planeswalker icon at the far left edge
2. **Foil detection** — reading the separator character (• or ★) between the set code and language code

The full card image often does not have sufficient resolution for these small details. If no close-up is provided, do not assume the icon is absent; only identify The List / Mystery Booster when the visible evidence is sufficient, otherwise leave the determination uncertain.

**How to identify the icon in the close up:**

The bottom-left info strip has two lines of text:
- **Top line:** `<collector number> / <total>  <rarity letter>`
- **Bottom line:** `<set code>  •  <language>  <artist name>`

The List/Mystery Booster icon (also known as the Planeswalker icon), when present, is a tall white glyph that sits at the **far left edge** of the info strip, spanning the full height of both lines. Its top half (five upward tines) aligns with the collector number; its bottom half (a pointed stem) reaches into the set code line.

**Critical distinction:** The set code text (e.g., `M19`, `BBD`) appears in the **middle of the bottom line**, after the bullet `•`. It is text, not an icon, and it is not at the far left. Do not confuse the set code with the List icon — they are in completely different positions.

The Planeswalker icon shape: a solid, handprint-like / crown-like glyph with five tines at the top narrowing to a single point at the bottom — a stylized five-pronged flame or splayed hand. Always white.

**IMPORTANT - Do NOT confuse with Artist Brush Icon:**
Near the artist name on the right side of the bottom line, there may be a small paint brush icon. This is the **artist credit icon**, NOT the List/Mystery Booster icon. The artist brush:
- Appears on the RIGHT side near the artist name
- Does NOT span both lines
- Is NOT at the far left edge
- Is a standard element on many cards and does NOT indicate a List reprint

Only the Planeswalker icon (five-tined glyph) at the FAR LEFT EDGE indicates a List/Mystery Booster reprint.

- **When the Planeswalker icon is present at the far left edge** → List/Mystery Booster reprint → `list_reprint: "yes"`, `list_symbol_visible: true`
- **No Planeswalker icon present at the far left edge** → original printing → `list_reprint: "no"`, `list_symbol_visible: false`
- **Cannot clearly identify the Planeswalker icon** (dark, blurry, cropped) → `list_reprint: "possible"`, `list_symbol_visible: false`

- List/Mystery Booster reprints retain the original set code, collector number, and art. The Planeswalker icon at the far left edge is the only indicator.
- On foil cards or very dark borders, the Planeswalker icon may be hard to see — default to `"possible"` if uncertain.

**The default is `"possible"`, not `"no"`.** You need positive visual confirmation that there is NO Planeswalker icon at the far left edge to return `"no"`. Dark, shadowed, or ambiguous → `"possible"`.

**Consistency rule:** `list_symbol_visible: true` and `list_reprint: "no"` is a contradiction. If you set `list_symbol_visible: true`, you MUST set `list_reprint: "yes"`.

### Other Printing Variant Markers
- **Promo indicator text** (e.g., "Prerelease", "Buy-a-Box", "FNMP", "Judge Gift") — appears near the bottom of the card. Transcribe verbatim if visible.
- **Collector number suffixes**: `e` suffix (e.g., `375e`) indicates an etched foil variant. `★` next to the collector number indicates a premium/promo printing in some older sets.
- **Pre-Modern shooting star**: a small shooting star icon in the lower-left corner indicates a pre-8th Edition foil (distinct from the Planeswalker icon).

---

## Step 4: Foil Detection

Evaluate foil signals in this order of reliability:

### 1. Separator character (most reliable when legible — modern cards only)
- `•` between SET CODE and LANG → non-foil
- `★` between SET CODE and LANG → foil
- **Use the close-up image to read this character** — it is small and the full card image often lacks resolution
- If unreadable even in the close-up, proceed to visual signals.

### 2. Pre-Modern shooting star (pre-8th Edition cards only)
A small shooting star icon in the lower-left corner of the card face indicates a pre-Modern era foil. This is distinct from the Planeswalker icon used for List/Mystery Booster reprints.

### 3. Visual sheen (apply conservatively)
Genuine traditional foil produces a **prismatic rainbow color shift visible across the full card surface** — including borders, frame, text box area, and artwork simultaneously.

**Do NOT call foil based on:**
- Rainbow or bright patches limited to the artwork area only — this is likely a photography lighting artifact or artistic style choice.
- A single bright glare spot or reflection — common with sleeves and hard cases.
- The M15-era oval holofoil security stamp on the P/T box — present on all rares/mythics regardless of foil status.
- A general dark/shiny appearance — many cards in sleeves or hard cases appear glossy.

### 4. Default when ambiguous
If the separator is unreadable and visual evidence is ambiguous, set `foil: false` and document what was observed in `foil_evidence`.

---

## Step 5: Early Set Identification (Pre-Symbol Era)

For cards with **no expansion symbol** (Alpha, Beta, Unlimited, Revised, 4th Edition, 5th Edition, and some Core Sets through 5th), use this decision tree:

### A. Border color first
| Border | Candidates |
|--------|-----------|
| Black  | Alpha, Beta (or foreign black border / Collectors Edition reprints) |
| White  | Unlimited, Revised, 4th Edition, 5th Edition |

### B. Copyright / illustrator credit line format
This is the single most important discriminator for white-border early cards. Transcribe it verbatim.

The bottom of early cards has two components:
1. **Illustrator line** (bottom-left): `Illus. [©] [Artist Name]`
2. **Copyright year** (same line, far right, or on a separate line below): `© [year] Wizards of the Coast`

The copyright year is the most important discriminator. It appears to the right of the artist credit on the same line — and is **frequently cut off by the photo frame**.

| What you can read | Interpretation |
|---|---|
| `Illus. © [Artist]` + `© 1993 Wizards of the Coast` visible | Alpha or Beta (black border only) |
| `Illus. © [Artist]` + `© 1994 Wizards of the Coast` visible | Revised (3rd Edition) |
| `Illus. © [Artist]` + `© 1995 Wizards of the Coast` visible | 4th Edition |
| `Illus. © [Artist]` + `© 1997 Wizards of the Coast` visible | 5th Edition |
| `Illus. © [Artist]` — **no copyright year visible, white border** | **Ambiguous**: could be Unlimited, Revised, 4th, or 5th — copyright year is cut off. Do NOT default to Unlimited. Report as uncertain. |
| `Illus. © [Artist]` — **no copyright year visible, black border** | Alpha or Beta — use corner rounding to distinguish |

**Unlimited Edition identification**: Unlimited is only confirmed when BOTH conditions are met:
1. White border
2. No copyright year is present anywhere on the card (including when zoomed in on the full bottom edge)

If you can only see `Illus. © [Artist]` and cannot see the rest of the bottom-right of the card, you CANNOT confirm Unlimited — Revised (1994), 4th Edition (1995), and 5th Edition (1997) all use the same illustrator line format. Report as "uncertain — Unlimited Edition or Revised Edition or 4th Edition" with low confidence.

### C. Rules text wording (supporting signal only)
- "Summon [type]" instead of "Creature — [type]" → pre-6th Edition (pre-1999)
- "Bury" instead of "destroy, it can't be regenerated" → pre-6th Edition
- "Cannot" instead of "can't" → likely Alpha/Beta/Unlimited era

These confirm era but do not distinguish between specific sets. Always prefer the copyright line over rules text for set identification.

### D. Alpha vs. Beta (black border only)
Both have identical text. The only reliable visual discriminator is corner rounding:
- Alpha: noticeably rounder corners than modern cards
- Beta: corners closer to modern card proportions

If corners are not clearly visible or are ambiguous, report as `"Alpha or Beta — indistinguishable from image"`.

### E. No set symbol ≠ Unlimited
Do not default to "Unlimited" when a card has no set symbol. Follow the credit line format above. Many pre-symbol cards are more common (and less valuable) 4th or 5th Edition printings.

---

## Step 6: Set Symbol Identification

For cards with a visible expansion symbol (mid-right, between art and text box):
- Symbol **color** indicates rarity: black = common, silver = uncommon, gold = rare, orange-red = mythic rare (post-2008).
- Identify the symbol shape where possible. If unreadable or ambiguous, report as `unknown`.
- For cards from Arabian Nights through Exodus (1993–1998), all set symbols are black regardless of rarity — do not use color for rarity on these cards.

---

## Split / Aftermath / Fuse Cards

Cards divided into two halves are ONE card, not two.
- Return the full combined name with ` // ` separator: e.g., `"Fire // Ice"`, `"Warrant // Warden"`.
- Do NOT return split card halves as separate entries.
- The collector number is shared by both halves.

---

## Output Schema

Return valid JSON only. No commentary outside the JSON block.

```json
{
  "cards": [
    {
      "title": "string — exact printed title",
      "edition": "string — the three-letter set code visible on the card (e.g., 'WAR', 'M10', '40K'), or 'unknown' if not visible",
      "edition_notes": "string — reasoning for edition assignment, especially for early cards",
      "collector_number": "string — the numeric collector number ONLY, with suffix letters like 'e' or '★' if present. Use 'none' for pre-Exodus cards without collector numbers",
      "foil": "boolean",
      "foil_type": "string — one of: none | rainbow_traditional | pre_modern_shootingstar | etched | textured | confetti | ripple | galaxy | halo | raised | unknown",
      "foil_evidence": ["array of strings — list each observed signal and what it indicates"],
      "list_reprint": "string — one of: yes | no | possible",
      "list_symbol_visible": "boolean",
      "border_color": "string — white | black | unknown",
      "copyright_line": "string — verbatim transcription of bottom credit line, especially important for early cards",
      "promo_text": "string or null — verbatim if visible",
      "confidence": "number 0–1",
      "notes": "string — any uncertainty, ambiguity, or image quality issues"
    }
  ]
}
```

### Example output

```json
{
  "cards": [
    {
      "title": "Mana Leak",
      "edition": "DDN",
      "edition_notes": "Set code DDN visible. List icon (five-tined glyph) observed at far left edge of info strip — List or Mystery Booster reprint of DDN printing.",
      "collector_number": "064",
      "foil": false,
      "foil_type": "none",
      "foil_evidence": [
        "bullet separator visible between DDN and EN — non-foil confirmed"
      ],
      "list_reprint": "yes",
      "list_symbol_visible": true,
      "border_color": "black",
      "copyright_line": "DDN • EN Howard Lyon",
      "promo_text": null,
      "confidence": 0.95,
      "notes": "Title, collector number, and separator clearly legible."
    },
    {
      "title": "Plague Rats",
      "edition": "2ED",
      "edition_notes": "White border. Credit line reads 'Illus. © Anson Maddocks' with © before artist name and no copyright year — consistent with Unlimited. Rules text uses old wording.",
      "collector_number": "none",
      "foil": false,
      "foil_type": "none",
      "foil_evidence": [
        "no separator line present — pre-M15 format",
        "no rainbow sheen visible across card surface"
      ],
      "list_reprint": "no",
      "list_symbol_visible": false,
      "border_color": "white",
      "copyright_line": "Illus. © Anson Maddocks",
      "promo_text": null,
      "confidence": 0.82,
      "notes": "Cannot distinguish Unlimited from Alpha/Beta on border color alone — white border confirms Unlimited. Corner rounding not clearly visible."
    },
    {
      "title": "Misthollow Griffin",
      "edition": "AVR",
      "edition_notes": "AVR set symbol visible. Collector number 68/244 matches AVR. Pre-M15 format — no SET CODE/LANG separator line.",
      "collector_number": "68",
      "foil": true,
      "foil_type": "rainbow_traditional",
      "foil_evidence": [
        "prismatic rainbow sheen visible across full card surface including borders and text box — foil confirmed",
        "no separator line available — pre-M15 format card"
      ],
      "list_reprint": "possible",
      "list_symbol_visible": false,
      "border_color": "black",
      "copyright_line": "© 1993–2012 Wizards of the Coast LLC",
      "promo_text": null,
      "confidence": 0.78,
      "notes": "Foil confirmed visually. List icon not visible at far left edge — may be obscured by foil sheen on pre-M15 card. Cannot confirm original AVR printing vs. List/Mystery Booster reprint from image alone."
    }
  ]
}
```
