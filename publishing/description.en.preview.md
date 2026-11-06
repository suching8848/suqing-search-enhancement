# SuQing's Search Enhancement

Search logic inspired by Minecraft JEI. Find carried and nearby items by name, source mod, full item ID and optional pinyin. Mark/count matches and prioritize matching groups in existing detailed lists.

**Opening and settings**
F8 opens Carried/Nearby search. Eight personal settings under Options > Mod Options > SuQing's Search Enhancement control field integration, counts, priority and available pinyin (on by default), click popup, expanded help and context entry (off), and the shortcut (F8). The core uses the game's built-in settings API with no external hard requirement.
A separate Sandbox Options > SuQing's Search Enhancement > Existing search-field handling setting defaults to all searches. Special syntax only keeps ordinary words/Chinese names with native matching and yellow highlights. @, &, -, |, quotes and whitespace AND activate enhancement; surrounding whitespace alone does not. The F8 panel always enhances searches. Missing values in old worlds use the default without editing the save.
Enhanced hits have purple outlines plus original yellow search highlights. Selection/hover retain their backgrounds and the match outline. Priority follows filtering, in-place sorting and rendering refreshes while preserving order within groups. Clearing/disabling priority restores native order; dragging, mouse holds and marquee selection defer reordering. Priority resumes after drag release without another item-list click.

**Queries**
brewing: partial name match.
@"Mod Name" brewing -book: source AND name, excluding book.
&Chinesecuisine.BrewingBook34: exact full ID, ignoring ASCII case.
wrench | hammer: either group; whitespace means AND and activates special handling.
"item name": quotes group text containing spaces.
@vanilla: game-identified vanilla source.
Names, type names and source display names ignore ASCII case and tolerate whitespace, hyphens, underscores and pinyin apostrophes. No spelling correction. Full IDs never use partial/pinyin matching. @ModID uses the real source ID, distinct from Base namespaces or Workshop IDs. Quotes do not enforce exact whitespace.

**Optional integrations and scope**
[Pinyin Search (yxjs_PinYinSearch 1.3)](https://steamcommunity.com/sharedfiles/filedetails/?id=3657184750): full spelling, initials and polyphonic alternatives, limited by its dictionary. NIUROUBING/NRB can find 牛肉饼; M110BQ can find M110 步枪. Its code/dictionary are not bundled.
[CleanUI 2.10.4](https://steamcommunity.com/sharedfiles/filedetails/?id=3437629766): field integration retains categories and synchronizes text/scope. Other UIs can use F8; custom fields require adapters.
[Proximity Inventory](https://steamcommunity.com/sharedfiles/filedetails/?id=2847184718): listed, readable physical sources with instance-based deduplication. All integrations are optional.
Targets B42.21 single-player detailed lists; icon grids are not adapted. Carried reads listed inventory/bags; Nearby reads accessible, explored containers and visible floor items. No world scanning, exploration or loot generation. Items/save structures are unchanged; queries are session-only. Exit normally, disable and restart to remove UI behavior. Manual/Workshop copies share one Mod ID; keep one loading source.

**Validation and assets**
On 2026-11-07 the user confirmed the 0.1.2 search-priority fix in their current local B42.21 single-player setup; 1147 offline assertions passed. Exhaustive sandbox modes, complete English UI, controllers, all third-party combinations, other versions, multiplayer and performance gains remain unverified.
Cover/separate transparent icon use AI-assisted artwork; the character is not an in-game skin/outfit. Thanks to integration authors; upstream rights remain theirs.

Mod ID: SuQingSearchEnhancement
