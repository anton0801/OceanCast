# Ocean Cast

A home food inventory that tracks real batches instead of a wish list.

---

## 1. What the app is

Ocean Cast keeps a record of the food a household actually owns: how much is
left of each purchase, where it is stored, the date the owner wrote down, and
how much of it is already promised to a planned meal.

It is not a shopping-list app with a pantry feature bolted on. The shopping list
is the last step of a chain that starts when a purchase is recorded. Nothing in
the app is entered twice.

Everything works offline on one device. An account is optional and only adds
sync between devices plus a server-side copy.

## 2. The problem it solves

People buy food they already have, and throw away food they forgot about. Both
happen for the same reason: at the moment of the decision — standing in a shop,
or opening the fridge at 19:40 — nobody knows what is at home and how much of it
is left.

Existing apps fail in three specific ways, and Ocean Cast is built against them:

- They merge purchases. Two bottles of milk bought a week apart become "2 milk",
  which destroys the dates and the prices. Ocean Cast keeps every purchase as a
  separate batch.
- They confuse "in stock" with "available". Four eggs in the fridge with three
  already assigned to tomorrow's omelette is one egg you can actually use.
  Ocean Cast tracks On hand and Available separately.
- They fill empty screens with fake numbers. An app that shows "0 items expiring"
  when it has no dates is lying. Ocean Cast writes Unknown and says which step is
  missing.

## 3. How the data moves

One chain, six links. Every step is triggered by the user; nothing happens on
its own.

```
purchase  →  batch  →  reservation  →  shortfall  →  shopping line  →  purchase
```

1. **A purchase creates a batch.** Scan a barcode, type it in, or read a receipt.
   The batch stores its own quantity, unit, date, price and storage zone.
2. **Use reduces the batch.** Every change asks for a reason: Used, Spilled,
   Corrected or Discarded. The reason is what makes the waste statistics real.
3. **A planned meal reserves ingredients.** Reserving lowers Available and never
   touches On hand. Cancelling the meal returns the reservation.
4. **What the meal cannot cover becomes a shortfall.** It stays a shortfall until
   the user confirms it; only then does it appear on the shopping list.
5. **Marking a line purchased creates a new batch** and records the price. The
   same line can never create two batches.
6. **The price feeds price history**, the usage feeds the statistics, and the
   cycle starts again.

Delete anything and the app lists what depends on it first. Archiving is offered
as the reversible alternative.

## 4. Screens

**Home.** Expiring soon, low stock, planned meals, items to buy, recall alerts,
and one Next Action computed from all of them. Every tile opens the records it
was calculated from. A tile with no data says why, and links to the step that
fills it.

**Household.** Name, currency, members, storage zones (Pantry, Fridge, Freezer,
or your own), shopping preferences. Removing a member keeps everything they
recorded. Archiving a zone keeps the items in it.

**Add product.** Barcode scan, catalogue search, manual entry. A catalogue answer
pre-fills the form and shows its source and time; the user confirms every field
before it is saved. An unknown barcode opens the manual form with the number
already filled in. A camera failure never clears what was typed.

**Receipt import.** A photo becomes a draft of lines, not stock. Each line carries
the recognition confidence; anything below the threshold is marked Needs Review.
Inventory changes only after Confirm Import. The photo can be deleted afterwards.

**Inventory.** Batches grouped by product and storage zone, filtered by Expiring,
Opened, Reserved or Low Stock. Identical products never merge across different
dates and prices; the group opens into its batches. Quantity can never go
negative, and a batch reserved for a meal cannot be quietly emptied.

**Product details.** On hand, reserved, available, price, source, every change
ever made to the batch, the meals holding it and any recall check. Amounts can be
shown in any compatible unit; pieces are never converted into grams.

**Expiry review.** A queue ordered by the date the user entered. Actions: Still
Good for Me (requires a new date), Use Today, Freeze, Discard, Edit Date. The
screen states plainly that the app cannot judge whether food is safe.

**Meal builder.** Name, servings, date, ingredients per serving. Check Stock
compares units and batches and reports coverage per ingredient. Reserve
Ingredients locks what exists. Missing amounts reach the shopping list only after
an explicit confirmation.

**Smart use ideas.** Ranks the meals the user saved against current stock and the
nearest dates. Every result explains its score: coverage weighs 65%, date
pressure 35%. It invents no recipes and needs at least three items in stock
before it will rank anything.

**Shopping plan.** Confirmed shortfalls plus manual lines, grouped by store.
Mark Purchased asks for the real quantity and price, then creates the batch.
Repeating it does nothing. Automatic lines can be excluded, with a reason.
Sharing produces plain text — the app does not order anything.

**Price history.** Only prices the user confirmed. Comparison converts to price
per base unit within one dimension; packs and weights are never mixed. Every
figure carries its store and date.

**Recall center.** Official notices from the U.S. FDA enforcement feed, matched
on this device against the user's own batches by barcode, brand, lot code or
product word. The match is always explained, and only the user can confirm that a
notice involves their batch. The app forwards the authority's instruction and
writes none of its own.

**Insights.** After 30 days of history: waste by reason, frequently refilled,
average basket, items often forgotten. Before that it shows the progress instead
of a number. Every figure opens its source records. Purchases with no recorded
price are counted as unknown, not as zero.

**Settings and data.** Units, expiry window, notification rules, JSON and CSV
export, backup import validated before it replaces anything, household deletion
with the counts it will remove, account deletion.

## 5. Rules the app follows everywhere

- No demo data. A fresh install is empty and says what to do first.
- Unknown is written as Unknown. An empty field is never treated as zero.
- Every computed number opens the records behind it.
- External data always shows its source and the time it was fetched. Offline,
  a stored snapshot is shown as a snapshot, with its age.
- Forms keep what was typed when something fails, validate next to the field,
  and block a second submit.
- Deleting explains the consequences and offers archiving instead.
- The app never claims food is safe or unsafe.

## 6. Data sources

| Source | Used for | What leaves the device |
|---|---|---|
| Open Food Facts | barcode lookup | the barcode |
| openFDA (U.S. FDA) | recall notices | nothing |
| Apple Vision | receipt text recognition | nothing — runs on device |
| Ocean Cast API | sync between devices | your own records, over HTTPS |

## 7. What it deliberately does not do

- No automatic shelf-life prediction. Dates come from the user.
- No fake recipe generation. Ideas are ranked from meals the user saved.
- No ordering, delivery or store integration.
- No ads, no analytics, no tracking.
- Photos stay on the device; only the file name is synced.
- Recall coverage is U.S. FDA food enforcement only, which the app states.

## 8. Technical outline

- iOS 18.5+, iPhone and iPad. SwiftUI, no third-party dependencies.
- Local storage is a JSON document in Application Support, written atomically.
  A file that cannot be read is preserved and reported, never overwritten.
- Sync is push-then-pull in one request, with tombstones for deletes and
  microsecond cursors. A record edited on another device wins over a stale push,
  and the conflict is reported rather than merged silently.
- API: PHP 8.1+ and MySQL 8, no framework. Argon2id passwords, opaque bearer
  tokens stored only as SHA-256 hashes, refresh rotation with reuse detection,
  per-IP and per-account rate limits, whitelist validation, prepared statements.
- Tokens live in the Keychain, marked this-device-only, and are cleared on the
  first launch after a reinstall.

---

## App Store listing

**Name:** Ocean Cast

**Subtitle:** Know what's in your kitchen

**Promotional text:**
Track real batches, not a vague list. See what is left, what is reserved for a
meal, and what actually needs buying.

**Description:**

Ocean Cast tells you what food you have at home, how much of it is left, and
what is already promised to a meal you planned.

Every purchase is stored as its own batch, with its own date, price and place.
Two bottles of milk bought a week apart stay two records, so a date is never
lost and a price is never averaged away.

Plan a meal and the app checks it against your actual stock. What exists gets
reserved, which lowers what is available without touching what is on hand. What
is missing waits for your confirmation before it reaches the shopping list. Mark
a line purchased and it becomes a new batch, with its price kept for next time.

Add items by scanning a barcode, typing them in, or photographing a receipt.
Receipt lines start as a draft you check line by line; nothing enters your
inventory until you confirm it.

The app also checks official U.S. FDA recall notices against the barcodes,
brands and lot codes of your own batches. It shows you why a notice might involve
your item and links to the official guidance. You decide whether it is a match.

Everything works offline. An account is optional and only adds sync between
devices.

What Ocean Cast does not do: it does not guess expiry dates, invent recipes,
show demo data, or claim that food is safe. Dates are yours. When something is
unknown, it says Unknown instead of showing a zero.

- Separate batches keep dates and prices apart
- On hand and Available tracked separately
- Storage zones: pantry, fridge, freezer, or your own
- Barcode scanning with a catalogue lookup you confirm
- Receipt import with per-line confidence
- Meal planning with a real stock check
- Shopping list built from confirmed shortfalls
- Price history from your own purchases
- Recall notices matched locally against your items
- Waste and refill statistics after 30 days of use
- Full JSON and CSV export, and one-tap account deletion
- No ads, no analytics, no tracking

**Keywords:** pantry,inventory,expiry,food waste,grocery,shopping list,meal plan,
barcode,fridge,freezer,stock,recall

**Category:** Food & Drink. Secondary: Productivity.

**Age rating:** 4+
