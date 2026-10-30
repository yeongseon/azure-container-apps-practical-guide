#!/usr/bin/env python3
"""Fixture-based contract tests; run with python3 scripts/test_diagram_inventory.py."""

import copy
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest
from collections.abc import Callable

import diagram_inventory as inventory

try:
    import jsonschema
except ImportError:  # the scanner works without it; only the parity test needs it
    jsonschema = None

ROOT = Path(__file__).resolve().parents[1]


class ParsingTests(unittest.TestCase):
    def test_unusable_frontmatter_ids_never_attach(self):
        for entry in ({}, {'id': None}, {'id': ''}, {'id': 42}, {'id': []}, {'id': {}}, {'id': '   '}):
            with self.subTest(entry=entry):
                text = '---\ncontent_sources:\n  diagrams: ' + json.dumps([entry]) + '\n---\n```mermaid\nflowchart LR\n```\n'
                records, errors, _ = inventory.page_records('x.md', text)
                self.assertEqual(records[0]['provenance']['status'], 'missing')
                self.assertIsNone(records[0]['provenance']['declared'])
                self.assertTrue(records[0]['id_provisional'])
                self.assertEqual(records[0]['key'], 'x.md#~1')
                self.assertEqual(errors['frontmatter_entries_without_fence'], [{'page': 'x.md', 'entry': entry}])

    def test_duplicate_frontmatter_ids_keep_first_and_report_count(self):
        text = '---\ncontent_sources:\n  diagrams: [{id: x, note: first}, {id: x, note: second}, {id: x, note: third}]\n---\n<!-- diagram-id:x -->\n```mermaid\nflowchart LR\n```\n'
        records, errors, _ = inventory.page_records('x.md', text)
        self.assertEqual(records[0]['provenance']['declared'], {'id': 'x', 'note': 'first'})
        self.assertEqual(errors['frontmatter_duplicate_ids'], [{'page': 'x.md', 'id': 'x', 'count': 3}])

    def test_empty_comment_id_is_provisional(self):
        records, _, _ = inventory.page_records('x.md', '<!-- diagram-id: -->\n```mermaid\nflowchart LR\n```')
        self.assertIsNone(records[0]['diagram_id'])
        self.assertTrue(records[0]['id_provisional'])
        self.assertEqual(records[0]['key'], 'x.md#~1')

    def test_duplicate_suffix_avoids_literal_and_provisional_keys(self):
        text = ''.join(f'<!-- diagram-id:{identifier} -->\n```mermaid\nflowchart LR\n```\n'
                       for identifier in ('x', 'x', 'x~2', '~5')) + '```mermaid\nflowchart LR\n```\n'
        records, _, _ = inventory.page_records('x.md', text)
        self.assertEqual([r['key'] for r in records], ['x.md#x', 'x.md#x~3', 'x.md#x~2', 'x.md#~5', 'x.md#~5~2'])
        self.assertEqual(len({r['key'] for r in records}), len(records))

    def test_heading_preserves_attached_hash(self):
        found, _ = inventory.fences('# C#\n## Child ###\n```mermaid\nflowchart LR\n```')
        self.assertEqual(found[0].headings, ('C#', 'Child'))

    def test_backtick_info_cannot_contain_backticks(self):
        found, _ = inventory.fences('```mermaid `invalid`\nflowchart LR\n```')
        self.assertEqual(found, [])

    def test_identifier_colon_needs_no_space(self):
        found, _ = inventory.fences('<!-- diagram-id:X -->\n```mermaid\nflowchart LR\n```')
        self.assertEqual(found[0].diagram_id, 'X')

    def test_unrecognized_fences_are_reported(self):
        for prefix, reason, before, after in [
                ('', 'html-comment', '<!-- hidden\n', '-->\n'),
                ('> ', 'blockquote', '', ''),
                ('    ', 'indented', '- item\n', '')]:
            for marker in ('```', '~~~~'):
                with self.subTest(reason=reason, marker=marker):
                    records, errors, _ = inventory.page_records('x.md', before + prefix + marker + 'mermaid extra\n' + prefix + 'flowchart LR\n' + prefix + marker + '\n' + after)
                    self.assertEqual(records, [])
                    self.assertEqual(errors['unrecognized_mermaid_fences'], [{'page': 'x.md', 'line': 2 if before else 1, 'reason': reason}])

    def test_html_comment_closes_and_single_line_comment_is_unaffected(self):
        text = '<!-- hidden\n```mermaid\nflowchart LR\n```\n-->\n<!-- diagram-id:X -->\n```mermaid\nflowchart LR\n```\n'
        records, errors, _ = inventory.page_records('x.md', text)
        self.assertEqual([r['diagram_id'] for r in records], ['X'])
        self.assertEqual(len(errors['unrecognized_mermaid_fences']), 1)

    def test_outer_fence_does_not_report_container_examples(self):
        text = '`````markdown\n> ```mermaid\n    ~~~mermaid\n<!-- hidden\n`````\n<!-- diagram-id:X -->\n```mermaid\nflowchart LR\n```\n'
        records, errors, _ = inventory.page_records('x.md', text)
        self.assertEqual([r['diagram_id'] for r in records], ['X'])
        self.assertNotIn('unrecognized_mermaid_fences', errors)

    def test_indented_mermaid_prose_is_not_a_fence(self):
        records, errors, _ = inventory.page_records('x.md', '    mermaid is prose\n    ```text mermaid\n    ```mermaidx\n')
        self.assertEqual(records, [])
        self.assertNotIn('unrecognized_mermaid_fences', errors)

    def test_fence_variants(self):
        text = '# Title\n## Child\n<!-- diagram-id: x -->\n\n   ~~~~mermaid extra\nflowchart LR\nA-->B\n~~~\n~~~~~\n'
        found, errors = inventory.fences(text)
        self.assertEqual(len(found), 1)
        self.assertEqual(found[0].diagram_id, 'x')
        self.assertEqual(found[0].headings, ('Title', 'Child'))
        self.assertEqual(found[0].body, 'flowchart LR\nA-->B\n~~~')
        self.assertEqual(errors, [])

    def test_nested_example(self):
        records, _, excluded = inventory.page_records('example.md', '````markdown\n```mermaid\nflowchart LR\nA-->B\n```\n````\n')
        self.assertEqual(len(records), 1)
        self.assertEqual(excluded[0]['kind'], 'example')

    def test_unclosed(self):
        found, errors = inventory.fences('```mermaid\nflowchart LR\n')
        self.assertFalse(found[0].closed)
        self.assertEqual(errors, [1])

    def test_id_must_be_adjacent_nonblank(self):
        found, _ = inventory.fences('<!-- diagram-id: old -->\nparagraph\n```mermaid\nflowchart LR\n```')
        self.assertIsNone(found[0].diagram_id)

    def test_duplicate_ids(self):
        fence = '<!-- diagram-id: same -->\n```mermaid\nflowchart LR\n```\n'
        records, errors, _ = inventory.page_records('x.md', fence * 3)
        self.assertEqual([r['key'] for r in records], ['x.md#same', 'x.md#same~2', 'x.md#same~3'])
        self.assertEqual([r['id_provisional'] for r in records], [False, True, True])
        self.assertEqual([r['diagram_id'] for r in records], ['same'] * 3)
        self.assertEqual(errors['duplicate_ids_on_page'], [{'key': 'x.md#same', 'count': 3,
                         'keys': ['x.md#same', 'x.md#same~2', 'x.md#same~3']}])

    def test_missing_ids_use_ordinals(self):
        records, errors, _ = inventory.page_records('x.md', '```mermaid\nflowchart LR\n```\n' * 2)
        self.assertEqual([r['key'] for r in records], ['x.md#~1', 'x.md#~2'])
        self.assertTrue(all(r['id_provisional'] and r['diagram_id'] is None for r in records))
        self.assertEqual(errors['missing_id_comment'], ['x.md#~1', 'x.md#~2'])

    def test_sibling_frontmatter_metadata(self):
        text = '---\nslug: arbitrary\ncontent_sources:\n  references: [{url: example}]\n  diagrams: [{id: x, extra: [true]}]\n---\n<!-- diagram-id: x -->\n```mermaid\nflowchart LR\n```\n'
        records, errors, _ = inventory.page_records('docs/x.md', text)
        self.assertEqual(records[0]['provenance']['declared'], {'id': 'x', 'extra': [True]})
        self.assertEqual(errors, {})

    def test_verbatim_unknown_provenance(self):
        text = '---\ncontent_sources:\n  diagrams:\n    - id: x\n      source: self-generated\n      justification: "Exact  spacing"\n      future: {a: [1, true]}\n    - id: orphan\n---\n<!-- diagram-id: x -->\n```mermaid\nflowchart LR\n```'
        records, errors, _ = inventory.page_records('x.md', text)
        self.assertEqual(records[0]['provenance']['declared'], {'id': 'x', 'source': 'self-generated', 'justification': 'Exact  spacing', 'future': {'a': [1, True]}})
        self.assertEqual(errors['frontmatter_entries_without_fence'][0]['entry'], {'id': 'orphan'})

    def test_frontmatter_variants(self):
        for header, status in [('', 'missing'), ('---\ncontent_sources: []\n---\n', 'malformed'), ('---\ncontent_sources: {references: []}\n---\n', 'missing'), ('---\nx: [\n---\n', 'malformed')]:
            with self.subTest(header=header):
                records, _, _ = inventory.page_records('x.md', header + '```mermaid\nflowchart LR\n```')
                self.assertEqual(records[0]['provenance']['status'], status)

    def test_genre_signals(self):
        for body, expected in [('flowchart LR\nA-->B', 'flow'), ('graph LR\nsubgraph X\nA-->B\nend', 'topology'), ('flowchart LR\nA{Ready?} -->|Yes| B', 'decision'), ('graph LR\nsubgraph X\nA{Ready?}-->B\nend', 'unknown'), ('sequenceDiagram\nA->>B: hi', 'sequence'), ('stateDiagram-v2\nA-->B', 'state'), ('pie\n"A": 1', 'chart'), ('timeline\n2026: event', 'timeline')]:
            with self.subTest(body=body):
                self.assertEqual(inventory.classify(body)[1], expected)


class AssignmentTests(unittest.TestCase):
    def __init__(self, methodName: str = 'runTest') -> None:
        super().__init__(methodName)
        self.diagram: inventory.Record = {}
        self.rules: inventory.Record = {}

    def setUp(self) -> None:
        self.diagram = inventory.diagram_record('docs/platform/x.md', 1, inventory.Occurrence(1, 3, 'x', (), 'flowchart LR', ''))
        self.rules = {'ownership_rules': [
            {'id': 'a', 'paths': ['docs/**'], 'priority': 1, 'batch_issue': 1, 'rationale': 'platform'},
            {'id': 'b', 'paths': ['docs/platform/*'], 'priority': 2, 'batch_issue': 2, 'rationale': 'topic'}], 'overrides': {}}

    def test_priority_records_all_candidates(self):
        result, error = inventory.assign(self.diagram, self.rules)
        self.assertEqual((result['batch_issue'], result['candidates'], error), (2, ['a', 'b'], None))

    def test_equal_priority_overlap(self):
        self.rules['ownership_rules'][0]['priority'] = 2
        _, error = inventory.assign(self.diagram, self.rules)
        assert error is not None
        self.assertEqual(error['key'], 'docs/platform/x.md#x')

    def test_override_wins(self):
        self.rules['overrides'][self.diagram['key']] = {'batch_issue': 3, 'rationale': 'reviewed distinction'}
        result, error = inventory.assign(self.diagram, self.rules)
        self.assertEqual((result['batch_issue'], result['method'], error), (3, 'override', None))

    def test_explicit_residual(self):
        self.rules['ownership_rules'][1]['residual'] = True
        result, _ = inventory.assign(self.diagram, self.rules)
        self.assertEqual(result['method'], 'residual-rule')

    def test_no_match_is_error(self):
        self.rules['ownership_rules'] = []
        _, error = inventory.assign(self.diagram, self.rules)
        self.assertIsNotNone(error)


class TreeTests(unittest.TestCase):
    def __init__(self, methodName: str = 'runTest') -> None:
        super().__init__(methodName)
        self.root: Path = Path(tempfile.gettempdir())
        self.rules: inventory.Record = {}

    def setUp(self) -> None:
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        (self.root / 'scripts').mkdir()
        (self.root / 'docs/reference').mkdir(parents=True)
        for relative in (inventory.SCRIPT, inventory.SCHEMA):
            _ = shutil.copyfile(ROOT / relative, self.root / relative)
        self.rules = {'repository': 'fixture', 'batches': [{'issue': 1, 'title': 'Fixture', 'phase': 'P0', 'scope': 'Fixture diagrams', 'owns_diagrams': True}], 'ownership_rules': [{'id': 'fixture', 'paths': ['*.md', 'docs/**'], 'priority': 1, 'batch_issue': 1, 'rationale': 'Fixture scope'}], 'overrides': {}, 'occurrence_exclusions': [{'id': 'example', 'paths': ['example.md'], 'kind': 'example', 'reason': 'Authoring example'}], 'asset_exclusions': [{'id': 'shots', 'group': 'screenshots', 'paths': ['docs/assets/*.png'], 'reason': 'Portal capture'}], 'visuals': []}
        _ = (self.root / inventory.RULES).write_text(inventory.encoded(self.rules))
        _ = (self.root / 'docs/x.md').write_text('<!-- diagram-id: x -->\n```mermaid\nflowchart LR\nA-->B\n```\n')

    def build(self) -> inventory.Record:
        return inventory.build(self.root, self.rules, '0' * 40)

    def visual_manifest(self) -> inventory.Record:
        value = self.build()
        value['visuals'] = [{'key': 'visual:x', 'kind': 'cytoscape', 'pages': ['docs/x.md'],
                             'sources': ['docs/graph.json'], 'assignment': copy.deepcopy(value['diagrams'][0]['assignment']),
                             'disposition': 'migration-required', 'rationale': 'Published graph'}]
        value['totals']['non_mermaid_visuals'] = 1
        return value

    def test_visual_ownership_and_keys(self):
        baseline = self.visual_manifest()
        self.assertEqual(inventory.check(self.root, baseline, self.rules), [])
        mutations: list[tuple[str, Callable[[inventory.Record], None], str]] = [
            ('unknown-batch', lambda m: m['visuals'][0]['assignment'].update(batch_issue=999), 'invalid owning batch'),
            ('non-owning', lambda m: m['batches'][0].update(owns_diagrams=False), 'visual:x: invalid owning batch'),
            ('duplicate', lambda m: m['visuals'].append(copy.deepcopy(m['visuals'][0])), 'visuals: duplicate key'),
            ('collision', lambda m: m['visuals'][0].update(key=m['diagrams'][0]['key']), 'visuals: key collides'),
            ('count', lambda m: m['totals'].update(non_mermaid_visuals=0), 'totals.non_mermaid_visuals')]
        for name, mutate, message in mutations:
            with self.subTest(mutation=name):
                value = copy.deepcopy(baseline)
                mutate(value)
                self.assertTrue(any(message in e for e in inventory.check(self.root, value, self.rules)))

    def test_excluded_visual_schema_parity(self):
        schema = json.loads((self.root / inventory.SCHEMA).read_text())
        value = self.visual_manifest()
        value['visuals'][0].update(disposition='excluded-pending-owner-decision', rationale='Branding only')
        value['visuals'][0]['assignment'].update(method='excluded', batch_issue=None, rationale='Branding only')
        self.assertEqual(inventory.check(self.root, value, self.rules), [])
        mutations: list[Callable[[inventory.Record], None]] = [
            lambda m: m['visuals'][0]['assignment'].update(batch_issue=1),
            lambda m: m['visuals'][0].update(rationale=''),
            lambda m: m['visuals'][0]['assignment'].update(rationale=''),
            lambda m: m['visuals'][0]['assignment'].update(rationale='   ')]
        for mutate in mutations:
            with self.subTest(mutation=mutate):
                changed = copy.deepcopy(value)
                mutate(changed)
                self.assertTrue(inventory.structural(changed, schema, schema['$defs']))
                self.assertTrue(inventory.check(self.root, changed, self.rules))
                if jsonschema is not None:
                    self.assertFalse(jsonschema.Draft202012Validator(schema).is_valid(changed))

    def test_visual_disposition_is_free_text(self):
        schema = json.loads((self.root / inventory.SCHEMA).read_text())
        excluded = self.visual_manifest()
        excluded['visuals'][0]['assignment'].update(method='excluded', batch_issue=None, rationale='Owner decision pending')
        for base in (self.visual_manifest(), excluded):
            for disposition in ('excluded', 'excluded-pending-owner-decision', 'migration-required', 'other'):
                with self.subTest(method=base['visuals'][0]['assignment']['method'], disposition=disposition):
                    value = copy.deepcopy(base)
                    value['visuals'][0]['disposition'] = disposition
                    self.assertEqual(inventory.structural(value, schema, schema['$defs']), [])
                    self.assertEqual(inventory.check(self.root, value, self.rules), [])
                    if jsonschema is not None:
                        self.assertTrue(jsonschema.Draft202012Validator(schema).is_valid(value))

    def test_new_exception_schema_is_closed(self):
        schema = json.loads((self.root / inventory.SCHEMA).read_text())
        for name, entry in [('frontmatter_duplicate_ids', {'page': 'x.md', 'id': 'x', 'count': 2}),
                            ('unrecognized_mermaid_fences', {'page': 'x.md', 'line': 1, 'reason': 'blockquote'})]:
            value = self.build()
            value['exceptions'][name] = [entry]
            self.assertEqual(inventory.structural(value, schema, schema['$defs']), [])
            for changed in ({**entry, 'extra': True}, {k: v for k, v in entry.items() if k != 'page'},
                            {**entry, 'count': 1} if 'count' in entry else {**entry, 'reason': 'other'}):
                with self.subTest(name=name, entry=changed):
                    value['exceptions'][name] = [changed]
                    self.assertTrue(inventory.structural(value, schema, schema['$defs']))
                    if jsonschema is not None:
                        self.assertFalse(jsonschema.Draft202012Validator(schema).is_valid(value))

    def test_unrecognized_write_warns_check_blocks_only_rendered(self):
        for reason, text in [('html-comment', '<!-- hidden\n```mermaid\nflowchart LR\n```\n-->\n'),
                             ('blockquote', '> ```mermaid\n> flowchart LR\n> ```\n'),
                             ('indented', '- item\n    ```mermaid\n    flowchart LR\n    ```\n')]:
            with self.subTest(reason=reason):
                _ = (self.root / 'docs/x.md').write_text(text + text)
                written = self.cli('--write', '--base-commit', '0' * 40)
                self.assertEqual(written.returncode, 0, written.stderr)
                self.assertEqual(len(written.stderr.splitlines()), 1)
                self.assertIn('docs/x.md:', written.stderr)
                checked = self.cli('--check')
                self.assertEqual(checked.returncode, 0 if reason == 'html-comment' else 1, checked.stdout)
                self.assertIn(reason, checked.stdout)
                if reason != 'html-comment':
                    self.assertIn('docs/x.md:', checked.stdout)
                    self.assertIn('move', checked.stdout)

    def test_bom_preserves_frontmatter_association(self):
        _ = (self.root / 'docs/x.md').write_text('\ufeff---\ncontent_sources:\n  diagrams: [{id: x}]\n---\n<!-- diagram-id:x -->\n```mermaid\nflowchart LR\n```\n')
        self.assertEqual(self.build()['diagrams'][0]['provenance']['status'], 'declared')

    def test_non_utf8_is_recorded_like_unparseable_frontmatter(self):
        _ = (self.root / 'docs/x.md').write_bytes(b'\xff```mermaid\n')
        written = self.cli('--write', '--base-commit', '0' * 40)
        self.assertEqual(written.returncode, 0, written.stderr)
        value = json.loads((self.root / inventory.MANIFEST).read_text())
        self.assertEqual(value['diagrams'], [])
        self.assertEqual(value['exceptions']['frontmatter_unparseable'][0]['page'], 'docs/x.md')
        self.assertIn('UTF-8', value['exceptions']['frontmatter_unparseable'][0]['error'])

    def test_suffix_collision_keys_pass_check(self):
        _ = (self.root / 'docs/x.md').write_text(''.join(f'<!-- diagram-id:{identifier} -->\n```mermaid\nflowchart LR\n```\n' for identifier in ('x', 'x', 'x~2')))
        value = self.build()
        self.assertEqual(len({d['key'] for d in value['diagrams']}), 3)
        self.assertEqual(inventory.check(self.root, value, self.rules), [])

    def test_generated_tables_have_blank_before_end_and_are_idempotent(self):
        page = self.root / inventory.PAGE
        _ = page.write_text('\n'.join(f'<!-- BEGIN GENERATED: diagram-inventory:{n} -->\nstale\n<!-- END GENERATED: diagram-inventory:{n} -->' for n in ('section', 'type', 'batch', 'exclusions', 'exceptions')))
        written = self.cli('--write', '--base-commit', '0' * 40)
        self.assertEqual(written.returncode, 0, written.stderr)
        first = page.read_bytes()
        lines = page.read_text().splitlines()
        for index, line in enumerate(lines):
            if line.startswith('<!-- END GENERATED:'):
                self.assertEqual(lines[index - 1], '')
        self.assertEqual(self.cli('--check').returncode, 0)
        self.assertEqual(self.cli('--write').returncode, 0)
        self.assertEqual(page.read_bytes(), first)

    def test_tree_label_drift_is_advisory_for_check(self):
        _ = (self.root / inventory.MANIFEST).write_text(inventory.encoded(self.build()))
        path = self.root / 'docs/x.md'
        _ = path.write_text(path.read_text().replace('A-->B', 'A[Changed label]-->B'))
        checked = self.cli('--check')
        self.assertEqual(checked.returncode, 0, checked.stdout)
        advisory = self.cli('--verify-tree')
        self.assertEqual(advisory.returncode, 0)
        self.assertEqual(json.loads(advisory.stdout)['changed'], ['docs/x.md#x'])

    def cli(self, *args: str) -> subprocess.CompletedProcess[str]:
        return subprocess.run([sys.executable, str(self.root / inventory.SCRIPT), '--root', str(self.root), *args], cwd=tempfile.gettempdir(), capture_output=True, text=True, env={**os.environ, 'PYTHONDONTWRITEBYTECODE': '1'})

    def test_determinism(self):
        first = self.cli('--write', '--base-commit', '0' * 40)
        self.assertEqual(first.returncode, 0, first.stderr)
        before = (self.root / inventory.MANIFEST).read_bytes()
        second = self.cli('--write')
        self.assertEqual(second.returncode, 0, second.stderr)
        self.assertEqual(before, (self.root / inventory.MANIFEST).read_bytes())

    def test_asset_grouping_and_unclassified(self):
        (self.root / 'docs/assets').mkdir()
        _ = (self.root / 'docs/assets/a.png').write_bytes(b'fixture')
        _ = (self.root / 'loose.svg').write_text('<svg/>')
        with (self.root / 'docs/x.md').open('a') as handle:
            _ = handle.write('![shot](assets/a.png)\n![again](assets/a.png)\n')
        result = self.build()
        self.assertEqual(result['exclusions']['assets'][0]['referenced_count'], 2)
        self.assertEqual(result['exceptions']['unclassified_assets'], ['loose.svg'])

    def test_exclusion(self):
        _ = shutil.copyfile(self.root / 'docs/x.md', self.root / 'example.md')
        result = self.build()
        self.assertEqual(result['totals']['excluded_occurrences'], 1)
        self.assertEqual(result['totals']['migration_required'], 1)
        self.assertEqual(result['totals']['by_batch'], {'1': 1})
        self.assertEqual(result['batches'][0]['count'], 1)
        self.assertEqual(result['totals']['by_assignment_method'], {'excluded': 1, 'rule': 1})
        excluded: inventory.Record = next(d for d in result['diagrams'] if d['page'] == 'example.md')
        self.assertEqual(excluded['assignment'], {'batch_issue': None, 'method': 'excluded',
                         'rule': 'example', 'candidates': ['fixture'], 'rationale': 'Authoring example'})
        self.assertEqual(inventory.check(self.root, result, self.rules), [])

    def test_exclusion_key_invariant(self):
        value = self.build()
        value['exclusions']['occurrences'].append({'key': 'absent', 'kind': 'example', 'reason': 'fixture'})
        self.assertTrue(any('keys must exactly match' in e for e in inventory.check(self.root, value, self.rules)))

    def test_nested_exclusion_needs_no_owner(self):
        _ = (self.root / 'example.md').write_text('````markdown\n```mermaid\nflowchart LR\n```\n````\n')
        self.rules['ownership_rules'] = []
        (self.root / 'docs/x.md').unlink()
        value = self.build()
        self.assertEqual(value['diagrams'][0]['assignment']['rule'], 'nested-fence-example')
        self.assertEqual(value['totals']['by_batch'], {})
        self.assertEqual(inventory.check(self.root, value, self.rules), [])

    def test_duplicate_keys_pass_check(self):
        path = self.root / 'docs/x.md'
        _ = path.write_text(path.read_text() * 3)
        self.assertEqual(inventory.check(self.root, self.build(), self.rules), [])

    def test_reused_ids(self):
        _ = shutil.copyfile(self.root / 'docs/x.md', self.root / 'docs/y.md')
        self.assertEqual(self.build()['exceptions']['id_reused_on_other_pages'], {'x': ['docs/x.md', 'docs/y.md']})

    def test_preserve_reviewed_fields(self):
        previous = self.build()
        diagram: inventory.Record = previous['diagrams'][0]
        diagram['classification']['review_status'] = 'reviewed'
        diagram['genre_candidate'] = 'topology'
        diagram['context']['reader_intent'] = 'Identify boundaries'
        diagram['target']['base'] = 'Container Apps environment'
        diagram['target']['extensions'] = ['candidate']
        diagram['target']['overlays'] = ['annotation']
        diagram['needs_review'] = False
        previous['diagrams'].append({**copy.deepcopy(diagram), 'key': 'gone.md#gone'})
        _ = (self.root / inventory.MANIFEST).write_text(inventory.encoded(previous))
        outcome = self.cli('--write')
        self.assertEqual(outcome.returncode, 0, outcome.stderr)
        regenerated: inventory.Record = json.loads((self.root / inventory.MANIFEST).read_text())
        actual: inventory.Record = regenerated['diagrams'][0]
        self.assertEqual(len(regenerated['diagrams']), 1)
        self.assertEqual((actual['genre_candidate'], actual['classification']['review_status'], actual['context'], actual['target'], actual['migration']), (diagram['genre_candidate'], 'reviewed', diagram['context'], diagram['target'], diagram['migration']))
        unchanged = self.cli('--verify-tree', '--strict')
        self.assertEqual(unchanged.returncode, 0, unchanged.stdout)
        self.assertFalse(any(json.loads(unchanged.stdout).values()))

    def test_generated_blocks_write_and_check(self):
        page = self.root / inventory.PAGE
        _ = page.write_text('# Inventory\n<!-- BEGIN GENERATED: diagram-inventory:section -->\nstale\n<!-- END GENERATED: diagram-inventory:section -->\n')
        manifest = self.build()
        _ = (self.root / inventory.MANIFEST).write_text(inventory.encoded(manifest))
        stale = self.cli('--check')
        self.assertEqual(stale.returncode, 1)
        self.assertIn('stale generated blocks', stale.stdout)
        written = self.cli('--write')
        self.assertEqual(written.returncode, 0, written.stderr)
        self.assertIn('| docs-root | 1 |', page.read_text())
        self.assertNotIn('stale', page.read_text())
        checked = self.cli('--check')
        self.assertEqual(checked.returncode, 0, checked.stdout)

    def test_generated_blocks_all_tables(self):
        page = self.root / inventory.PAGE
        names = ('section', 'type', 'batch', 'exclusions', 'exceptions')
        _ = page.write_text('\n'.join(f'<!-- BEGIN GENERATED: diagram-inventory:{n} -->\nstale\n<!-- END GENERATED: diagram-inventory:{n} -->' for n in names))
        _, updated = inventory.generated_page(self.root, self.build())
        assert updated is not None
        self.assertNotIn('stale', updated)
        self.assertEqual(updated.count('| Count |'), 5)

    def test_generated_blocks_unmatched(self):
        for marker in ('BEGIN', 'END'):
            with self.subTest(marker=marker):
                _ = (self.root / inventory.PAGE).write_text(f'<!-- {marker} GENERATED: diagram-inventory:section -->')
                with self.assertRaisesRegex(inventory.InventoryError, 'unmatched generated marker section'):
                    _ = inventory.generated_page(self.root, self.build())

    def test_generated_blocks_reversed_or_repeated(self):
        begin = '<!-- BEGIN GENERATED: diagram-inventory:section -->'
        end = '<!-- END GENERATED: diagram-inventory:section -->'
        for text in (end + begin, begin + end + begin, begin + end + begin + end):
            with self.subTest(text=text):
                _ = (self.root / inventory.PAGE).write_text(text)
                with self.assertRaisesRegex(inventory.InventoryError, 'unmatched generated marker section'):
                    _ = inventory.generated_page(self.root, self.build())

    def test_generated_page_absent(self):
        self.assertEqual(inventory.generated_page(self.root, self.build()), (None, None))

    def test_compact_encoding(self):
        value = self.build()
        first = inventory.encoded(value)
        self.assertEqual(first, inventory.encoded(value))
        self.assertEqual(json.loads(first), value)
        self.assertTrue(first.endswith('\n'))
        self.assertNotIn('\r', first)
        for field in ('diagrams', 'batches', 'candidate_components'):
            for entry in value[field]:
                compact = json.dumps(entry, ensure_ascii=False, sort_keys=True, separators=(',', ':'))
                self.assertIn('    ' + compact, first.splitlines())
        self.assertLess(max(map(len, first.splitlines())), 6000)

    def test_compact_baseline_line_budget(self):
        value: inventory.Record = json.loads((ROOT / inventory.MANIFEST).read_text())
        text = inventory.encoded(value)
        self.assertLess(max(map(len, text.splitlines())), 6000)
        self.assertLess(len(text.splitlines()), 1500)
        self.assertEqual(json.loads(text), value)

    def test_check_failure_messages(self):
        baseline = self.build()
        mutations: list[tuple[str, Callable[[inventory.Record], None], str]] = [('count', lambda m: m['totals'].update(occurrences=99), 'totals.occurrences'), ('hash', lambda m: m['baseline'].update(rules_sha256='0' * 64), 'hash differs'), ('batch', lambda m: m['diagrams'][0]['assignment'].update(batch_issue=999), 'invalid owning batch'), ('key', lambda m: m['diagrams'][0].update(key='wrong'), 'key does not match')]
        for name, mutate, message in mutations:
            with self.subTest(name=name):
                value = copy.deepcopy(baseline)
                mutate(value)
                _ = (self.root / inventory.MANIFEST).write_text(inventory.encoded(value))
                result = self.cli('--check')
                self.assertEqual(result.returncode, 1)
                self.assertIn(message, result.stdout)

    def test_verify_tree_detects_drift(self):
        _ = (self.root / inventory.MANIFEST).write_text(inventory.encoded(self.build()))
        _ = (self.root / 'docs/y.md').write_text('```mermaid\nsequenceDiagram\nA->>B: hi\n```')
        result = self.cli('--verify-tree', '--strict')
        self.assertEqual(result.returncode, 1)
        self.assertEqual(json.loads(result.stdout)['added'], ['docs/y.md#~1'])

    def test_verify_tree_drift_categories(self):
        original = (self.root / 'docs/x.md').read_text()
        for name in ('removed', 'moved', 'changed', 'reclassified'):
            with self.subTest(category=name):
                path = self.root / 'docs/x.md'
                _ = path.write_text(original)
                _ = (self.root / inventory.MANIFEST).write_text(inventory.encoded(self.build()))
                if name == 'removed':
                    path.unlink()
                elif name == 'moved':
                    _ = path.rename(self.root / 'docs/new.md')
                elif name == 'changed':
                    _ = path.write_text(original.replace('A-->B', 'A-->C'))
                else:
                    _ = path.write_text(original.replace('flowchart LR\nA-->B', 'sequenceDiagram\nA->>B: hi'))
                outcome = self.cli('--verify-tree', '--strict')
                self.assertEqual(outcome.returncode, 1, outcome.stderr)
                difference: inventory.Record = json.loads(outcome.stdout)
                expected = [{'from': 'docs/x.md#x', 'to': 'docs/new.md#x'}] if name == 'moved' else ['docs/x.md#x']
                self.assertEqual(difference[name], expected)
                moved = self.root / 'docs/new.md'
                if moved.exists():
                    moved.unlink()

    @unittest.skipIf(jsonschema is None, 'jsonschema is not installed')
    def test_schema_mutation_parity(self):
        assert jsonschema is not None
        schema: inventory.Record = json.loads((self.root / inventory.SCHEMA).read_text())
        validator = jsonschema.Draft202012Validator(schema)
        baseline: inventory.Record = json.loads((ROOT / inventory.MANIFEST).read_text())
        self.assertEqual(inventory.structural(baseline, schema, schema['$defs']), [])
        self.assertTrue(validator.is_valid(baseline))
        mutations: list[tuple[str, Callable[[inventory.Record], None]]] = [
            ('wrong-type', lambda m: m['diagrams'][0].update(ordinal='1')),
            ('missing-key', lambda m: m['diagrams'][0].pop('context')),
            ('extra-key', lambda m: m['diagrams'][0]['location'].update(extra=True)),
            ('genre', lambda m: m['diagrams'][0].update(genre_candidate='verified')),
            ('method', lambda m: m['diagrams'][0]['classification'].update(method='verified')),
            ('review', lambda m: m['diagrams'][0]['classification'].update(review_status='approved')),
            ('hash', lambda m: m['baseline']['scanner'].update(sha256='bad')),
            ('commit', lambda m: m['baseline'].update(base_commit='bad')),
            ('null-owner', lambda m: next(d for d in m['diagrams'] if d['assignment']['method'] != 'excluded')['assignment'].update(batch_issue=None)),
            ('excluded-owner', lambda m: next(d for d in m['diagrams'] if d['assignment']['method'] == 'excluded')['assignment'].update(batch_issue=407)),
            ('provenance', lambda m: m['diagrams'][0]['provenance'].update(status='verified')),
            ('verification', lambda m: m['diagrams'][0]['provenance'].update(verification='verified')),
            ('migration', lambda m: m['diagrams'][0]['migration'].update(state='complete')),
            ('target', lambda m: m['diagrams'][0]['target'].update(status='accepted')),
            ('exception', lambda m: m['exceptions']['frontmatter_unparseable'].append({'page': 'x', 'error': 2})),
            ('negative-count', lambda m: m['totals'].update(occurrences=-1)),
            ('bool-integer', lambda m: m.update(schema_version=True)),
        ]
        for name, mutate in mutations:
            with self.subTest(mutation=name):
                value = copy.deepcopy(baseline)
                mutate(value)
                self.assertTrue(inventory.structural(value, schema, schema['$defs']))
                self.assertFalse(validator.is_valid(value))

    def test_builtin_structural_validation(self):
        schema: inventory.Record = json.loads((self.root / inventory.SCHEMA).read_text())
        value = self.build()
        value['diagrams'][0]['classification']['method'] = 'verified'
        errors = inventory.structural(value, schema, schema['$defs'])
        self.assertTrue(any('invalid enum' in error for error in errors))


class IntegrationTests(unittest.TestCase):
    def test_current_tree_reproduction_requires_opt_in(self):
        reproduction = type(self).test_baseline_reproduction_in_temp_tree
        self.assertEqual(getattr(reproduction, '__unittest_skip__', False),
                         os.environ.get('DIAGRAM_INVENTORY_REPRODUCE') != '1')

    def test_baseline_check(self):
        if not (ROOT / inventory.MANIFEST).exists():
            self.skipTest('baseline not generated yet')
        manifest: inventory.Record = json.loads((ROOT / inventory.MANIFEST).read_text())
        rules: inventory.Record = json.loads((ROOT / inventory.RULES).read_text())
        self.assertEqual(inventory.check(ROOT, manifest, rules), [])

    @unittest.skipUnless(os.environ.get('DIAGRAM_INVENTORY_REPRODUCE') == '1',
                         'current-tree reproduction is opt-in: baseline is frozen at baseline.base_commit; tree drift is advisory')
    def test_baseline_reproduction_in_temp_tree(self):
        if not (ROOT / inventory.MANIFEST).exists():
            self.skipTest('baseline not generated yet')
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            paths = [p for p in inventory.tracked(ROOT) if p.endswith('.md') or Path(p).suffix.lower() in inventory.ASSETS]
            paths += [inventory.SCRIPT, inventory.RULES, inventory.SCHEMA, inventory.MANIFEST]
            for relative in paths:
                destination = root / relative
                destination.parent.mkdir(parents=True, exist_ok=True)
                _ = shutil.copyfile(ROOT / relative, destination)
            result = subprocess.run([sys.executable, str(root / inventory.SCRIPT), '--write'], capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual((root / inventory.MANIFEST).read_bytes(), (ROOT / inventory.MANIFEST).read_bytes())


if __name__ == '__main__':
    _ = unittest.main(verbosity=2)
