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

Price bounds use normal text fields: cursor edits, selection, and paste leave the
text unchanged while typing. Leaving a field formats valid input to two decimal
places using the current locale, without a currency symbol. An empty field removes
that bound. Invalid entries remain visible with an inline error and keep the last
valid bound; correct or clear them before continuing or closing with Done.
Each nonempty price field has an × button that immediately clears its text, error,
and bound. Focus stays in the cleared field with the keyboard open on iPhone.
On iPadOS 26.4.1, clearing can minimize the software keyboard while retaining
field focus; tap the field to reopen it. This known iPad limitation is deferred.
Other price bounds and filters are preserved. The clear-button space remains reserved in empty
fields so typing and clearing do not move the value or resize the row. Empty fields
show “Any” when unfocused and only the caret while focused.

The keyboard toolbar moves through Min Retail, Max Retail, Min Buylist, and Max
Buylist with Previous/Next arrows. Its checkmark completes the current entry and
hides the keyboard. These controls use an inset above the keyboard on iPhone and
iPad so they remain available at every text size. Hardware Return advances, or
completes the last field. Reset clears draft text, errors, and all filters.
Reopening loads committed bounds.

Lists refresh prices and buying quantities on entry and after printing or foil
identity changes. Failed refreshes retain cached data, and responses for an old
identity or deleted item are discarded. Availability reflects the backend’s last
CK data import, not a live checkout guarantee. Existing stores migrate with
unknown buying quantities until a successful lookup populates them.

Simulator routes `pricing-results`, `pricing-collection`, `pricing-deck`,
`pricing-large`, `pricing-filter`, `pricing-filter-editing`, and
`pricing-filter-invalid` exercise the production screens with fixture
prices and buying quantities. Run `make ios-snapshot ROUTE=pricing-results` after building.
