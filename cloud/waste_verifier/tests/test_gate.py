import os
import unittest

from waste_ai import apply_verification_gate


class VerificationGateTests(unittest.TestCase):
    def setUp(self):
        os.environ["WASTE_CONFIDENCE_THRESHOLD"] = "0.80"
        os.environ["WASTE_MIN_FRAMES"] = "2"

    def test_accepts_confident_multiframe_waste(self):
        result = apply_verification_gate({
            "decision": "verified_waste", "is_waste": True, "waste_confidence": 0.91,
            "frames_with_waste": [1, 2, 2], "items": [{"name": "bottle"}]
        })
        self.assertTrue(result["verification"]["verified"])
        self.assertEqual(result["frames_with_waste"], [1, 2])

    def test_rejects_random_or_single_frame_object(self):
        result = apply_verification_gate({
            "decision": "verified_waste", "is_waste": True, "waste_confidence": 0.95,
            "frames_with_waste": [3], "items": [{"name": "object"}]
        })
        self.assertFalse(result["verification"]["verified"])


if __name__ == "__main__":
    unittest.main()
