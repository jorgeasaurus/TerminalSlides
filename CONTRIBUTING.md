# Contributing

## Requirements

- PowerShell 7+
- Pester 5+

## Workflow

1. Import the module locally with `Import-Module ./TerminalSlides.psd1 -Force`
2. Run `./build.ps1`
3. Add or update tests with every functional change
4. Keep changes cross-platform and avoid host-specific assumptions

## Style

- Prefer small, composable functions
- Use approved verbs and cmdlet binding for public commands
- Avoid executing untrusted content during import or export
