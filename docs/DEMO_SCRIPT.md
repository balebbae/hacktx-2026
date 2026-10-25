# Familiar demo script (3 minutes, table-side)

Phone face-up on the table showing the Judge view. Wearer = "Priya" (set your real name in Settings → You). Marcus = the teammate who gets enrolled. One never-enrolled teammate = the stranger.

| # | Step | Trigger | Expected utterance(s) | Judge view |
|---|---|---|---|---|
| 0 | Walk slowly toward a wall or a pulled-out chair (Judge view on the phone) | automatic, every ~2.5 s | "Wall ahead, 3 meters." / "Chair ahead, close."; entering a new area: one short line like "Hallway, door at 1 o'clock." | Poyo panel: last uploaded image with faces blacked out, scene latency |
| 0b | Ask about the scene | "Poyo, what's in front of me?" then, without the wake word, "and is there a sign?" | chime at once, answer in ~2–3 s with clock directions; the follow-up needs no "Poyo" | Poyo panel lines + answer latency |
| 1 | Three people in view, none enrolled | Double-tap the glasses, volume-down, or "Poyo, who's here?" (or tap **Who's here?**) | "No one I know. Three people." | three grey "person" boxes |
| 2 | Marcus walks up, chats ~20 s ("Hi, I'm Marcus" … "Nice meeting you") | Goodbye phrase → quiet "Want to remember them?" to the wearer; or press capture / volume-up / tap **Remember them** | Phone speaker: "Priya would like to recognize you next time you meet. Okay to remember your face, Marcus?" (card with YES / NO) → Marcus: "Yes!" → glasses: "Saved. Marcus is in your contacts." | grey "person" box turns green "Marcus 0.7x"; People screen shows the consent clip |
| 3 | Marcus leaves, comes back from the right at ~2 m | automatic | "Marcus, coming from 1 o'clock." (or "coming toward you.") … "Marcus, next to you." (stretch: Marcus speaks first → "Marcus.") | green box tracks him |
| 4 | Stranger walks up | automatic | nothing is spoken about them | grey "person" box |
|   | Roll call | who's here trigger | "Marcus, 12 o'clock, close. One other person." | |
| 5 | Call | People → Marcus → **Call** (or "Poyo, call Marcus") | "Calling Marcus." → dialer opens | |

Close on the banner: *Known people only. Strangers are "a person". Faces are blacked out before any image leaves this phone.* (Show the Poyo panel's last uploaded image.) Then Meta's policy line: face identification is banned on these glasses except for approved accessibility apps; Familiar is built as that app, in Developer Mode, and Marcus can remove himself at any time (People → Marcus → Remove deletes the record, thumbnail, consent clip and the contact).

Reset between runs: long-press the Home title → Demo controls → Reset people.

## Fallback tiers (Settings → Source / Audio route)
1. Glasses camera (Bluetooth Classic) + glasses A2DP audio + phone mic.
2. Glasses camera over Wi-Fi + phone speaker.
3. Phone camera at chest height + glasses audio.
4. Phone camera + phone speaker.
5. Fixture clip in the Judge view + the recorded walkthrough.
