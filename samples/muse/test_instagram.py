"""Offline checks; never use real credentials, Instagram, Apify, or Muse."""
import json
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

import instagram as sample


def public_profile(**overrides):
    return {"username": "demo", "fullName": "Demo", "private": False,
            "biography": "Coffee photos", "latestPosts": [
                {"shortCode": "abc_123", "caption": "Morning coffee", "alt": "A blue mug",
                 "childPosts": [{"alt": "A blue mug"}, {"alt": "A table"}],
                 "latestComments": [{"text": "Do not collect this"}]}], **overrides}


def muse_response(**overrides):
    card = {"spoken_summary": "Demo posts coffee photos.",
            "topics": [{"topic": "Coffee photos", "source_ids": ["post_1"]}],
            "aesthetic": None, "aesthetic_source_ids": [], "limitations": ["Text only"], **overrides}
    return {"choices": [{"finish_reason": "stop", "message": {"content": json.dumps(card)}}]}


class SampleTests(unittest.TestCase):
    def test_handle_validation(self):
        self.assertEqual(sample.normalize_username(" @Demo "), "demo")
        for invalid in ("../secret", "a..b", "https://instagram.com/demo", ""):
            with self.assertRaises(sample.SampleError):
                sample.normalize_username(invalid)

    def test_public_profile_allowlist(self):
        profile = sample.normalize_profile(public_profile(email="private@example.com"), "demo")
        self.assertNotIn("email", profile)
        self.assertNotIn("latestComments", json.dumps(profile))
        self.assertEqual(profile["sources"][1]["image_descriptions"], ["A blue mug", "A table"])

    def test_reject_private_unknown_and_wrong_profile(self):
        for overrides in ({"isPrivate": True}, {"isPrivate": None}, {"username": "someone_else"}, {"error": "blocked"}):
            with self.assertRaises(sample.SampleError):
                sample.normalize_profile(public_profile(**overrides), "demo")

    def test_empty_posts_are_not_invented(self):
        profile = sample.normalize_profile(public_profile(latestPosts=[]), "demo")
        self.assertEqual(len(profile["sources"]), 1)

    def test_privacy_field_variants_and_missing_flag(self):
        item = public_profile()
        del item["private"]
        with self.assertRaises(sample.SampleError):
            sample.normalize_profile(item, "demo")
        item["isPrivate"] = False
        self.assertEqual(sample.normalize_profile(item, "demo")["username"], "demo")
        for value in (True, None, "false"):
            with self.assertRaises(sample.SampleError):
                sample.normalize_profile(public_profile(private=value), "demo")

    @patch("instagram.request_json")
    def test_scrape_then_cache_avoids_network(self, request):
        run = {"id": "run1", "status": "SUCCEEDED", "defaultDatasetId": "data1"}
        request.side_effect = [{"data": run}, [public_profile()]]
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            first = sample.fetch_profile("demo", "fake", root)
            self.assertEqual(sample.fetch_profile("demo", "fake", root), first)
        self.assertEqual(request.call_count, 2)
        self.assertEqual(request.call_args_list[0].args[2]["usernames"], ["demo"])

    @patch("instagram.request_json")
    def test_interrupted_run_resumes_even_with_refresh(self, request):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            sample.save_json(root / "demo.run.json", {"id": "run1", "status": "RUNNING"})
            request.side_effect = [{"data": {"id": "run1", "status": "SUCCEEDED", "defaultDatasetId": "data1"}}, [public_profile()]]
            sample.fetch_profile("demo", "fake", root, refresh=True)
            self.assertTrue(all(len(call.args) == 2 for call in request.call_args_list))

    @patch("instagram.request_json")
    def test_no_items_does_not_create_profile(self, request):
        request.side_effect = [{"data": {"id": "run1", "status": "SUCCEEDED", "defaultDatasetId": "data1"}}, []]
        with tempfile.TemporaryDirectory() as directory:
            with self.assertRaises(sample.SampleError):
                sample.fetch_profile("demo", "fake", Path(directory))
            self.assertFalse((Path(directory) / "demo.profile.json").exists())

    @patch("instagram.request_json")
    def test_valid_summary(self, request):
        request.return_value = muse_response()
        card = sample.summarize_profile(sample.normalize_profile(public_profile(), "demo"), "fake")
        self.assertEqual(card["model"], sample.MODEL)
        self.assertEqual(card["topics"][0]["source_ids"], ["post_1"])

    @patch("instagram.request_json")
    def test_reject_fabricated_source_or_visual_claim(self, request):
        profile = sample.normalize_profile(public_profile(latestPosts=[]), "demo")
        for response in (muse_response(), muse_response(topics=[], aesthetic="Colorful", aesthetic_source_ids=["bio"])):
            request.return_value = response
            with self.assertRaises(sample.SampleError):
                sample.summarize_profile(profile, "fake")

    @patch("instagram.request_json")
    def test_refusal_and_truncation_rejected(self, request):
        for finish in ("length", "content_filter"):
            result = muse_response()
            result["choices"][0]["finish_reason"] = finish
            request.return_value = result
            with self.assertRaises(sample.SampleError):
                sample.summarize_profile(sample.normalize_profile(public_profile(), "demo"), "fake")


if __name__ == "__main__":
    unittest.main()
