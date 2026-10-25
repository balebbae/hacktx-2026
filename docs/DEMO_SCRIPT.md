# Familiar demo script (3 minutes, table-side)

Phone face-up on the table showing the Judge view. Wearer = "Priya" (set your real name in Settings → You). Marcus = the teammate who gets enrolled. One never-enrolled teammate = the stranger.

| # | Step | Trigger | Expected utterance(s) | Judge view |
|---|---|---|---|---|
| 1 | Three people in view, none enrolled | Double-tap the glasses, volume-down, or "Familiar, who's here?" (or tap **Who's here?**) | "No one I know. Three people." | three grey "person" boxes |
| 2 | Marcus walks up, chats ~20 s ("Hi, I'm Marcus" … "Nice meeting you") | Goodbye phrase → quiet "Want to remember them?" to the wearer; or press capture / volume-up / tap **Remember them** | Phone speaker: "Priya would like to recognize you next time you meet. Okay to remember your face, Marcus?" (card with YES / NO) → Marcus: "Yes!" → glasses: "Saved. Marcus is in your contacts." | grey "person" box turns green "Marcus 0.7x"; People screen shows the consent clip |
| 3 | Marcus leaves, comes back from the right at ~2 m | automatic | "Marcus, coming from your right." … "Marcus, next to you." (stretch: Marcus speaks first → "Marcus.") | green box tracks him |
| 4 | Stranger walks up | automatic | nothing is spoken about them | grey "person" box |
|   | Roll call | who's here trigger | "Marcus, ahead, close. One other person." | |
| 5 | Call | People → Marcus → **Call** (stretch: "Familiar, call Marcus") | "Calling Marcus." → dialer opens | |

Close on the banner: *Known people only. Strangers are "a person". Faces never leave this phone.* Then Meta's policy line: face identification is banned on these glasses except for approved accessibility apps; Familiar is built as that app, in Developer Mode, and Marcus can remove himself at any time (People → Marcus → Remove deletes the record, thumbnail, consent clip and the contact).

Reset between runs: long-press the Home title → Demo controls → Reset people.

## Fallback tiers (Settings → Source / Audio route)
1. Glasses camera (Bluetooth Classic) + glasses A2DP audio + phone mic.
2. Glasses camera over Wi-Fi + phone speaker.
3. Phone camera at chest height + glasses audio.
4. Phone camera + phone speaker.
5. Fixture clip in the Judge view + the recorded walkthrough.
