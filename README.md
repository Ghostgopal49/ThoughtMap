# ThoughtMap

A private mind map for your iPhone. Press the Action Button, speak a thought, and Apple's on-device AI files it into a web of bubbles. Nothing leaves your phone.

## What's inside

- **Infinite canvas.** Drag the background to move around, pinch to zoom, tap ◎ to see everything.
- **Automatic sorting.** Each new thought goes to a cluster path such as *Projects › App ideas*, created if it doesn't exist yet.
- **You stay in charge.** Drag a thought onto any cluster to move it, drag a cluster to rearrange the map, or tap a bubble to rename, re-parent or delete it. The AI learns from your moves.
- **Loose web.** Dotted lines join thoughts that mean similar things, even across clusters.
- **Insights** (chart button). Where your attention is now, what's rising and fading over 8 weeks, and an on-device AI reflection.
- **Privacy.** Stored only in the app on your phone, with an option to keep it out of iCloud Backup and a JSON export.

Needs iOS 26 or later and Apple Intelligence switched on (Settings › Apple Intelligence & Siri). Without it, thoughts are grouped by similarity instead.

## Getting it onto your iPhone (no Mac, no $99)

### 1. Build it on GitHub (free)

1. Create a free account at github.com.
2. Create a new **private** repository called `ThoughtMap` (leave it empty).
3. Put these project files in it. Claude can push them for you, or upload them on the website with **Add file › Upload files** (include the `.github` folder).
4. Open the **Actions** tab. A build starts by itself and takes about 10 minutes.
5. When it's green, open **Releases** on the repository page. The newest release contains `ThoughtMap.ipa`.

Every change to the code produces a new release automatically.

### 2. Install SideStore (one time, on your PC)

1. Install **iTunes** on the PC so Windows can talk to the iPhone.
2. Download **iloader** from its official page: https://github.com/nab138/iloader
3. Connect the iPhone with a cable, open iloader, sign in with your Apple ID and choose to install SideStore. Some people use a second, spare Apple ID for this.
4. On the iPhone, turn on **Settings › Privacy & Security › Developer Mode** if asked, and restart.
5. Follow the SideStore docs (https://docs.sidestore.io) to install the small VPN helper app it uses to refresh apps without the PC.

### 3. Install ThoughtMap

1. On the iPhone, open the GitHub release in Safari and download `ThoughtMap.ipa`.
2. Open SideStore, go to **My Apps**, tap **+**, and pick the downloaded file.
3. Open SideStore every few days and refresh, so the 7-day signature never runs out. If it does run out, refreshing brings the app back and your thoughts are still there.
4. To update, install the newer `.ipa` the same way. Your thoughts are kept.

### 4. Set up the Action Button

1. Open **Shortcuts**, tap **+**.
2. Add **Dictate Text**.
3. Add **Add Thought** (from ThoughtMap). It picks up the dictated text automatically.
4. Name it *Capture thought*.
5. **Settings › Action Button** › Shortcut › *Capture thought*.

Press, speak, done. You'll hear where it was saved. If the AI can't run in the background at that moment, the thought waits in **Unsorted** and gets sorted next time you open the app.

You can also say *"Hey Siri, add a thought to ThoughtMap."*

## Tuning

- `Embeddings.swift`: how similar thoughts must be to get a dotted link (`relatedThreshold`).
- `Organizer.swift`: the instructions the AI follows when placing thoughts and writing reflections.
- `Layout.swift`: spacing of bubbles on the canvas.
