#!/usr/bin/env python3
# Copyright 2026 Maktab-e-Digital Systems Lahore.
# SPDX-License-Identifier: Apache-2.0
import unittest

from parse_results import ParseError, parse_coremark, parse_dhrystone


COREMARK_SAMPLE = """\
CoreMark Size    : 666
Total ticks      : 13176747
Iterations       : 40
Compiler version : GCC 16.1.0
Compiler flags   : -O2 -march=rv64imac_zicsr_zifencei_zicbom_zicboz -mabi=lp64
seedcrc          : 0x18f2
[0]crclist       : 0xe3c1
[0]crcmatrix     : 0x0747
[0]crcstate      : 0x8d84
[0]crcfinal      : 0xf006
Correct operation validated.
"""

DHRYSTONE_SAMPLE = """\
Dhrystone Benchmark, Version 2.1 (Language: C)
Execution starts, 10000 runs through Dhrystone
Execution ends
Final values of the variables used in the benchmark:
Int_Glob:            5
Bool_Glob:           1
Ch_1_Glob:           A
Ch_2_Glob:           B
Arr_1_Glob[8]:       7
Arr_2_Glob[8][7]:    10010
Ptr_Glob->
    Ptr_Comp:          129952
    Discr:             0
    Enum_Comp:         2
    Int_Comp:          17
    Str_Comp:          DHRYSTONE PROGRAM, SOME STRING
Next_Ptr_Glob->
    Ptr_Comp:          129952
    Discr:             0
    Enum_Comp:         1
    Int_Comp:          18
    Str_Comp:          DHRYSTONE PROGRAM, SOME STRING
Int_1_Loc:           5
Int_2_Loc:           13
Int_3_Loc:           7
Enum_Loc:            1
Str_1_Loc:           DHRYSTONE PROGRAM, 1'ST STRING
Str_2_Loc:           DHRYSTONE PROGRAM, 2'ND STRING
Total cycles:                                2340019
Cycles per run through Dhrystone:           234
"""


class DhrystoneParserTests(unittest.TestCase):
    def test_coremark_sample_still_parses(self):
        result = parse_coremark(COREMARK_SAMPLE, "temporary-spike")

        self.assertTrue(result["valid"])
        self.assertEqual(result["iterations"], 40)

    def test_valid_sample_includes_correctness_and_timing(self):
        result = parse_dhrystone(DHRYSTONE_SAMPLE, "temporary-spike")

        self.assertTrue(result["valid"])
        self.assertEqual(result["runs"], 10000)
        self.assertEqual(result["total_cycles"], 2340019)
        self.assertEqual(result["cycles_per_run"], 234)

    def test_wrong_expected_values_are_rejected_even_with_timing(self):
        invalid_outputs = (
            DHRYSTONE_SAMPLE.replace("Int_Glob:            5", "Int_Glob:            6", 1),
            DHRYSTONE_SAMPLE.replace("Arr_2_Glob[8][7]:    10010", "Arr_2_Glob[8][7]:    10009", 1),
            DHRYSTONE_SAMPLE.replace("DHRYSTONE PROGRAM, 2'ND STRING", "incorrect string", 1),
        )

        for output in invalid_outputs:
            with self.subTest(output=output):
                with self.assertRaises(ParseError):
                    parse_dhrystone(output)

    def test_missing_completion_marker_is_rejected(self):
        output = DHRYSTONE_SAMPLE.replace("Execution ends\n", "", 1)

        with self.assertRaisesRegex(ParseError, "did not complete"):
            parse_dhrystone(output)

    def test_missing_correctness_output_is_rejected(self):
        output = DHRYSTONE_SAMPLE.replace("Ptr_Glob->\n", "", 1)

        with self.assertRaisesRegex(ParseError, "final-value output"):
            parse_dhrystone(output)

    def test_missing_or_malformed_timing_is_rejected(self):
        invalid_outputs = (
            DHRYSTONE_SAMPLE.replace("Total cycles:                                2340019\n", "", 1),
            DHRYSTONE_SAMPLE.replace("Cycles per run through Dhrystone:           234", "Cycles per run through Dhrystone:           invalid", 1),
            DHRYSTONE_SAMPLE.replace("Cycles per run through Dhrystone:           234", "Cycles per run through Dhrystone:           235", 1),
        )

        for output in invalid_outputs:
            with self.subTest(output=output):
                with self.assertRaises(ParseError):
                    parse_dhrystone(output)

    def test_mismatched_pointer_values_are_rejected(self):
        output = DHRYSTONE_SAMPLE.replace(
            "Next_Ptr_Glob->\n    Ptr_Comp:          129952",
            "Next_Ptr_Glob->\n    Ptr_Comp:          129953",
            1,
        )

        with self.assertRaisesRegex(ParseError, "Next_Ptr_Glob Ptr_Comp"):
            parse_dhrystone(output)


if __name__ == "__main__":
    unittest.main()