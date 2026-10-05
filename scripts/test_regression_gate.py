# Copyright 2026 Maktab-e-Digital Systems Lahore.
# SPDX-License-Identifier: Apache-2.0
import copy
import unittest

from regression_gate import evaluate


COREMARK = {
    "benchmark": "coremark",
    "configuration": "temporary-spike",
    "total_ticks": 100,
    "iterations": 1,
    "valid": True,
}
DHRYSTONE = {
    "benchmark": "dhrystone",
    "configuration": "temporary-spike",
    "cycles_per_run": 100,
    "runs": 10,
    "valid": True,
}


def history(*results, accepted=True):
    return {"schema_version": 1, "entries": [{"accepted": accepted, "results": list(results)}]}


class RegressionGateTests(unittest.TestCase):
    def test_no_baseline(self):
        report = evaluate([COREMARK], {"schema_version": 1, "entries": []})
        self.assertEqual(report["comparisons"][0]["status"], "baseline")

    def test_same_metric_passes(self):
        report = evaluate([COREMARK], history(COREMARK))
        self.assertEqual(report["comparisons"][0]["status"], "pass")

    def test_improvement_passes(self):
        result = copy.deepcopy(COREMARK)
        result["total_ticks"] = 90
        self.assertTrue(evaluate([result], history(COREMARK))["passed"])

    def test_two_percent_regression_passes(self):
        result = copy.deepcopy(COREMARK)
        result["total_ticks"] = 102
        self.assertEqual(evaluate([result], history(COREMARK))["comparisons"][0]["status"], "pass")

    def test_exactly_three_percent_regression_passes(self):
        result = copy.deepcopy(COREMARK)
        result["total_ticks"] = 103
        self.assertTrue(evaluate([result], history(COREMARK))["passed"])

    def test_more_than_three_percent_regression_blocks(self):
        result = copy.deepcopy(COREMARK)
        result["total_ticks"] = 104
        self.assertEqual(evaluate([result], history(COREMARK))["comparisons"][0]["status"], "blocked")

    def test_invalid_result_is_rejected(self):
        result = copy.deepcopy(COREMARK)
        result["valid"] = False
        with self.assertRaisesRegex(ValueError, "valid must be true"):
            evaluate([result], {"schema_version": 1, "entries": []})

    def test_missing_metric_is_rejected(self):
        result = copy.deepcopy(COREMARK)
        del result["iterations"]
        with self.assertRaisesRegex(ValueError, "missing or invalid iterations"):
            evaluate([result], {"schema_version": 1, "entries": []})

    def test_non_positive_dhrystone_runs_are_rejected(self):
        result = copy.deepcopy(DHRYSTONE)
        result["runs"] = 0
        with self.assertRaisesRegex(ValueError, "runs must be positive"):
            evaluate([result], {"schema_version": 1, "entries": []})

    def test_failed_history_entry_is_ignored(self):
        result = copy.deepcopy(COREMARK)
        result["total_ticks"] = 200
        report = evaluate([COREMARK], history(result, accepted=False))
        self.assertEqual(report["comparisons"][0]["status"], "baseline")

    def test_configurations_do_not_share_baselines(self):
        baseline = copy.deepcopy(COREMARK)
        baseline["configuration"] = "config-a"
        current = copy.deepcopy(COREMARK)
        current["configuration"] = "config-b"
        self.assertEqual(evaluate([current], history(baseline))["comparisons"][0]["status"], "baseline")


if __name__ == "__main__":
    unittest.main()