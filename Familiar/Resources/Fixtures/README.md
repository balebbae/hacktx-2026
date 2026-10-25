Fixture clips (720×1280 H.264, AAC 64k) recorded on Sat Oct 24 2026 and transcoded with
`ffmpeg -i in.MOV -vf scale=720:1280 -c:v libx264 -crf 26 -c:a aac -b:a 64k out.mp4`.
`fixtures.json` lists expectations; `*.txt` are the transcripts for `FakeTranscriber` (`other:` = Marcus, `user:` = the wearer).
Missing: `no_reply.mp4`, `distance_calibration.mp4`, and the `*_hevc.mov` copies for the glasses Mock Device Kit
(`ffmpeg -i enroll_marcus.mp4 -c:v libx265 -tag:v hvc1 -an enroll_marcus_hevc.mov`).
