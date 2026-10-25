"""Offline checks for the relocated image experiment; no paid generation."""
import base64
import json
import unittest
from unittest.mock import MagicMock, patch

import image


class ImageTests(unittest.TestCase):
    def test_empty_prompt_rejected(self):
        with self.assertRaises(ValueError):
            image.generate_image("  ")

    @patch("image.api_key", return_value="test-key")
    @patch("image.urllib.request.urlopen")
    def test_request_and_decoded_output(self, urlopen, key):
        expected = b"\x89PNG\r\n\x1a\nexample"
        response = MagicMock()
        response.read.return_value = json.dumps({"data": [{"b64_json": base64.b64encode(expected).decode()}]}).encode()
        urlopen.return_value.__enter__.return_value = response
        self.assertEqual(image.generate_image(" A glowing tree "), expected)
        request = urlopen.call_args.args[0]
        body = json.loads(request.data)
        self.assertEqual(body["prompt"], "A glowing tree")
        self.assertEqual(body["model"], image.MODEL)
        self.assertEqual(body["response_format"], "b64_json")

    @patch("image.api_key", return_value="test-key")
    @patch("image.urllib.request.urlopen")
    def test_missing_image_rejected(self, urlopen, key):
        response = MagicMock()
        response.read.return_value = b'{"data": []}'
        urlopen.return_value.__enter__.return_value = response
        with self.assertRaises(RuntimeError):
            image.generate_image("A tree")


if __name__ == "__main__":
    unittest.main()
