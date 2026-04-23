# Findings: Library List Visual Glitch

**Date:** 2026-04-11  
**Work Effort:** 2026-04-10-list-visual-glitch  
**Author:** Ori  
**Status:** Research Complete - Gap Issue Unresolved

---

## Executive Summary

This document captures all findings from the investigation into the Library list visual glitch (unwanted rounded-row behavior during swipe interactions) and the subsequent attempt to fix header spacing issues with large navigation titles.

**Primary Issue (Resolved):** The rounded-row glitch was fixed by converting from `.insetGrouped` to `.plain` list style across all three list views (Library, Collection Detail, Deck Detail, Results).

**Secondary Issue (Unresolved):** Eliminating the gap between the search bar and the first list row when using `.plain` list style with large navigation titles proved intractable within SwiftUI's current constraints.

---

## Root Cause Analysis

### The Rounded-Row Glitch

**Problem:** List rows were displaying with rounded corners during swipe-to-delete interactions, creating an undesirable visual effect.

**Cause:** The views were using `.listStyle(.insetGrouped)` which applies rounded corners to row backgrounds as part of its design language. During swipe interactions, the background reveals these rounded corners.

**Solution:** Changed to `.listStyle(.plain)` which uses full-width rectangular rows without rounded corners.

### The Header/Title Coordination Problem

**Problem:** When using `.plain` list style with large navigation titles and section headers, the header title would disappear during scroll transitions or there would be excessive spacing between the search bar and the first row.

**Cause:** SwiftUI's `.plain` List with Section headers cannot properly coordinate with large navigation titles during scroll. The section header and navigation title "fight" each other during collapse/expand transitions. This is a known framework limitation.

**Attempted Solutions:**

1. **Section Headers with `.headerProminence(.increased)`** - Failed: Title still disappeared during scroll
2. **Floating Badge Overlay** - Rejected by user: Wanted traditional header appearance
3. **Fake Header Row (first item in list)** - Partially worked but gap remained
4. **`.listRowInsets(EdgeInsets())`** - Reduced but didn't eliminate gap
5. **Negative insets** - Had no visible effect
6. **Removing header background** - No improvement

---

## Files Modified

### Final State (All Three Views)

| File | Key Changes |
|------|-------------|
| `CollectionDetailView.swift` | `.listStyle(.plain)`, fake header row with `.listRowInsets(EdgeInsets(top: -8, ...))` |
| `DeckDetailView.swift` | Same pattern as CollectionDetailView |
| `ResultsView.swift` | Same pattern as CollectionDetailView |

### Pattern Used

```swift
List(selection: $selectedItems) {
    // Fake header as first row
    cardListHeader(for: items)
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets(top: -8, leading: 0, bottom: 0, trailing: 0))
        .disabled(true)
    
    ForEach(items) { cardRowView(for: $0) }
}
.listStyle(.plain)
```

---

## Technical Constraints Discovered

### SwiftUI Limitations

1. **`.plain` + Section Headers + Large Titles = Broken**
   - Section headers with `.plain` style cannot coordinate with large navigation titles
   - Header disappears during scroll transitions
   - Not fixable through view hierarchy adjustments alone

2. **`.insetGrouped` + Large Titles = Working but Rounded**
   - Works correctly with large titles
   - But introduces rounded corners (the original problem)

3. **Search Bar Spacing**
   - `.searchable` modifier adds its own spacing that cannot be easily overridden
   - The gap between search bar and first list row is framework-controlled

### UIKit Insight

In UIKit, the scrollable content must be the first subview in the hierarchy for proper large title coordination. SwiftUI abstracts this away, and `.plain` List breaks this assumption when combined with section headers.

---

## Decisions Made

| Decision | Rationale |
|----------|-----------|
| Keep `.plain` list style | User explicitly rejected `.insetGrouped` due to corner rounding glitch |
| Use fake header row | Only way to show header content without breaking large title behavior |
| Do not put count in navigation title | User rejected "Collection Name (42)" format as "looks terrible" |
| Do not use inline title mode | User rejected `.navigationBarTitleDisplayMode(.inline)` as title becomes "tiny and stuck in the corner" |
| Accept remaining gap | Framework limitation; no known SwiftUI workaround |

---

## Build Configuration

```bash
# Build command
xcodebuild -workspace apps/ios/MTGScanner.xcworkspace \
  -scheme MTGScanner \
  -destination "name=Brett's iPhone" \
  build

# Install command
xcrun devicectl device install app \
  --device "Bretts-iPhone.coredevice.local" \
  "/Users/brettvitaz/Library/Developer/Xcode/DerivedData/MTGScanner-ewzhyxijxhwysefkpnuasnwydgli/Build/Products/Debug-iphoneos/MTGScanner.app"

# Launch command
xcrun devicectl device process launch \
  --device "Bretts-iPhone.coredevice.local" \
  com.brettvitaz.mtgscanner \
  --terminate-existing \
  --activate
```

---

## Verification Results

- ✅ Build succeeds
- ✅ Install succeeds
- ✅ Launch succeeds
- ✅ Rounded-row glitch fixed (plain style)
- ✅ Swipe-to-delete works correctly
- ✅ Large title displays correctly
- ❌ Gap between search bar and first row remains

---

## Recommendations for Future Work

### Option 1: Accept Current State
The gap is a minor cosmetic issue. The core functionality works correctly:
- No rounded-row glitch
- Swipe actions work
- Large titles work
- Header shows card count

### Option 2: UIKit Interop
Use `UIViewControllerRepresentable` to wrap a UIKit `UITableView` with proper large title coordination. This would require:
- Custom UITableView implementation
- Proper `contentInsetAdjustmentBehavior` configuration
- Manual header view management

### Option 3: Redesign Without Large Titles
Use `.navigationBarTitleDisplayMode(.inline)` with a custom header that includes both the title and card count. This was rejected by user but technically works.

### Option 4: Wait for SwiftUI Updates
Apple may fix the `.plain` List + large title coordination in a future iOS release.

---

## Related Work

- PR #65: Contains the final implementation
- Branch: `list-visual-glitch`
- Build instructions: `/Users/brettvitaz/.openclaw/workspace/MTGScanner-Build-Instructions.md`

---

## Lessons Learned

1. **SwiftUI List styles have deep behavioral differences** - `.plain` and `.insetGrouped` are not just cosmetic; they affect scroll behavior, header pinning, and title coordination.

2. **Searchable adds non-configurable spacing** - The gap introduced by `.searchable` cannot be easily eliminated.

3. **Fake header rows are a viable workaround** - When Section headers break, making the header a regular row with `.disabled(true)` preserves functionality.

4. **Negative insets don't always work** - SwiftUI sometimes ignores or clamps negative edge insets.

5. **User testing on device is essential** - Simulator behavior differs from device, especially for navigation title animations.
