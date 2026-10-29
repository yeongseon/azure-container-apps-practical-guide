"""Regression fixtures for supported syntax, coverage, and declared limits."""

import pathlib
import tempfile
import unittest

from detect_absorbed_predicates import analyse, conjuncts, find_absorbed, load_allowlist


class AbsorptionTests(unittest.TestCase):
    def test_absorption_when_supported_forms_wrap_paths(self):
        for expression in ("s or f", "bool((s or f))", "bool(bool(s or f))", "s or t or f", "any([s, f])"):
            with self.subTest(expression=expression):
                given = f"s = a and b\nf = b\nt = c\nd_pass = {expression}"
                actual = find_absorbed(given)
                self.assertEqual([(f["wide"], f["narrow"]) for f in actual], [("s", "f")])

    def test_absorption_when_all_literal_builds_strong_path(self):
        for literal in ("[a, b, c]", "(a, b, c)", "{a, b, c}"):
            with self.subTest(literal=literal):
                given = f"s = all(\n    {literal}\n)\nf = b and c\nd_pass = s or f"
                actual = find_absorbed(given)
                self.assertEqual([f["result"] for f in actual], ["d_pass"])

    def test_cpu_shape_when_result_is_bool_wrapped(self):
        given = "d_strong = readme_exists and len(named_outputs) == len(PHASE_B_OUTPUTS)\nd_fallback = readme_exists\nd_pass = bool(d_strong or d_fallback)"
        actual = find_absorbed(given)
        self.assertEqual([f["narrow_expr"] for f in actual], ["readme_exists"])

    def test_revision_history_shape_when_false_initialized_guarded_generator(self):
        given = 's = False\nf = readme_exists\nif readme_exists:\n    s = all(\n        item["mentioned"] for item in records\n    )\nd_pass = s or f'
        actual = find_absorbed(given)
        self.assertEqual([f["result"] for f in actual], ["d_pass"])

    def test_any_when_literal_is_not_a_conjunction(self):
        given = "s = any([a, b])\nf = b\nd_pass = s or f"
        actual = find_absorbed(given)
        self.assertEqual(actual, [])

    def test_opaque_calls_when_generator_or_unknown_call(self):
        for atom in ("all(x for x in rows)", "all([x for x in rows])", "check(a, b)"):
            with self.subTest(atom=atom):
                given = f"s = {atom} and extra\nf = {atom}\nd_pass = s or f"
                actual = find_absorbed(given)
                self.assertEqual([f["result"] for f in actual], ["d_pass"])
                self.assertEqual(len(conjuncts(atom)), 1)

    def test_last_assignment_when_only_constant_initialization_precedes(self):
        given = "s = False\ns = a and b\nf = b\nd_pass = s or f"
        actual = find_absorbed(given)
        self.assertEqual([f["result"] for f in actual], ["d_pass"])

    def test_ambiguous_when_multiple_nonconstant_assignments_precede_use(self):
        given = "s = a and b\nif condition:\n    s = c\nf = b\nd_pass = s or f"
        findings, counts, skipped = analyse(given)
        self.assertEqual(findings, [])
        self.assertEqual(counts["ambiguous assignment"], 1)
        self.assertEqual(len(skipped), 1)

    def test_unknown_when_unsupported_or_missing_operands(self):
        for given, reason in (
            ("d_pass = s or f", "name without assignment"),
            ("d_pass = s or check()", "not a name"),
            ("d_pass = invalid ====", "unsupported construct"),
        ):
            with self.subTest(reason=reason):
                actual = analyse(given)
                self.assertEqual(actual[1][reason], 1)

    def test_no_inference_when_relational_or_arithmetic_implications(self):
        for strong, fallback in (("len(x) == n", "len(x) > 0"), ("n > 10", "n > 0"), ("x + 1 == 3", "x == 2")):
            with self.subTest(strong=strong):
                given = f"s = {strong}\nf = {fallback}\nd_pass = s or f"
                actual = find_absorbed(given)
                self.assertEqual(actual, [])

    def test_separate_scope_when_heredoc_ends(self):
        given = "s = a and b\nPY\nf = b\nd_pass = s or f"
        actual = analyse(given)
        self.assertEqual(actual[1]["name without assignment"], 1)

    def test_known_defect_when_issue_number_missing(self):
        with tempfile.TemporaryDirectory() as directory:
            path = pathlib.Path(directory) / "allowlist.txt"
            path.write_text("labs/x/verify.sh::d_pass::s::f # KNOWN-DEFECT: broken\n")
            with self.assertRaisesRegex(ValueError, "requires an issue number"):
                load_allowlist(path)

    def test_alias_expansion_is_outside_analysis_boundary(self):
        given = "referenced = readme_exists and all(refs.values())\ns = referenced\nf = readme_exists\nresult = s or f"
        self.assertEqual(find_absorbed(given), [])


if __name__ == "__main__":
    unittest.main()
