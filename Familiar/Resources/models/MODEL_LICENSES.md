# Model licenses

## w600k_mbf.onnx (InsightFace `buffalo_sc` pack)

- Source: https://github.com/deepinsight/insightface/releases/download/v0.7/buffalo_sc.zip (asset `w600k_mbf.onnx`, 13,616,099 bytes)
- SHA-256: `9cc6e4a75f0e2bf0b1aed94578f144d15175f357bdc05e815e5c4a02b319eb4f`
- Architecture: MobileFaceNet trained on WebFace600K with the ArcFace loss; input `1x3x112x112` float32 RGB, `(x - 127.5) / 127.5`, NCHW; output 512 floats (L2-normalised by the app).
- License: the InsightFace project code is MIT, but the pretrained models are released for **non-commercial research purposes only** (see https://github.com/deepinsight/insightface#license: "The pretrained models we provided with this library are available for non-commercial research purposes only, including both auto-downloading models and manual-downloading models."). Familiar is a hackathon demo and uses it under those terms; a commercial build must swap in a model with a permissive license (for example OpenCV Zoo SFace, Apache-2.0, 128-d).
- Training data: WebFace600K is a cleaned subset of WebFace42M (https://www.face-benchmark.org/) and carries its own research-only terms.
