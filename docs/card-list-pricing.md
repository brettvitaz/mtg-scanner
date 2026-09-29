# Card list pricing

Results, collection detail, and deck detail show quantity-weighted totals for the
cards currently visible after searching and filtering. Buylist is Card Kingdom’s
listed offer to buy a card; Retail is its selling price. The same terminology is
used in rows, details, sorting, and price filters.

Retail appears above Buylist, matching the card rows. Sort and Filter are vertically
centered beside the totals in a compact header, wrapping when screen width or text size
requires it. **More options → Show price totals** hides them and restores the original
count layout. This preference is shared across the three screens and survives
relaunch. The summary is hidden while selecting cards.

Missing prices are excluded and incomplete totals are marked **Partial**.
VoiceOver includes the number of priced copies. No available prices displays a
dash; no matching cards displays zero. Buying limits do not cap valuation totals.

**Filter → Card Kingdom → Show cards CK is buying** includes only cards with a
confirmed buying quantity greater than zero. Zero and unknown quantities are
excluded. With the filter off, rows identify **CK not buying** or **CK status
unknown** below the Buylist price; positive quantities are announced by VoiceOver
and shown in card details. Reset clears this filter along with the other filters.

Lists refresh prices and buying quantities on entry and after printing or foil
identity changes. Failed refreshes retain cached data, and responses for an old
identity or deleted item are discarded. Availability reflects the backend’s last
CK data import, not a live checkout guarantee. Existing stores migrate with
unknown buying quantities until a successful lookup populates them.

Simulator routes `pricing-results`, `pricing-collection`, `pricing-deck`,
`pricing-large`, and `pricing-filter` exercise the production screens with fixture
prices and buying quantities. Run `make ios-snapshot ROUTE=pricing-results` after building.
