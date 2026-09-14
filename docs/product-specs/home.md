# Home

Status: established roadmap direction and behavior supported by current TV composition.

Current composition (not a fixed product mandate for every shelf): Home presents a
Continue Watching row when content is available, followed by configured
and server-derived media shelves. Recently Added separates movies and shows on TV;
other shelves include optional Recently Played, library content, recommendations,
and Popular Movies. Empty/unavailable groups need not occupy space.

Do not add a separate Next Up shelf to TV Home. Eligible next episodes belong in
[Continue Watching](continue-watching.md). Section headings are non-interactive labels.
Selecting a Continue Watching tile opens the selected item's details in the current
implementation; preserve the [navigation contract](navigation.md).

Return users to their browsing context according to [focus restoration](focus-restoration.md).
Top Shelf exposes Continue Watching outside the app through a saved snapshot; do not
assume it is a separate live query or guaranteed to be as fresh as Home.

Implementation entry points: [DefaultContentGroupProvider](../../Shared/ViewModels/ContentGroupViewModel/DefaultContentGroupProvider.swift)
and [architecture map](../../ARCHITECTURE.md).
