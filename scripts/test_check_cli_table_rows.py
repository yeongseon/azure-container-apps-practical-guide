import tempfile
import unittest
from pathlib import Path

from check_cli_table_rows import command_requirements, validate_file


class CliTableRowTests(unittest.TestCase):
    def test_extracts_each_command_path_and_flag(self) -> None:
        commands, flags = command_requirements(
            [
                "az containerapp revision list \\",
                '  --name "$APP_NAME" --output table',
                "az containerapp revision show --revision rev",
            ]
        )
        self.assertEqual(
            commands,
            {"az containerapp revision list", "az containerapp revision show"},
        )
        self.assertEqual(flags, {"--name", "--output", "--revision"})

    def test_reports_missing_command_and_flag_rows(self) -> None:
        markdown = """```bash
az containerapp show --name app --resource-group rg
```

| Command | Purpose |
|---|---|
| `az containerapp show` | Shows the app. |
| `--name` | Selects the app. |

"""
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "sample.md"
            _ = path.write_text(markdown, encoding="utf-8")
            findings = validate_file(path)
        self.assertEqual(len(findings), 1)
        self.assertIn("--resource-group", findings[0].message)


if __name__ == "__main__":
    _ = unittest.main()
