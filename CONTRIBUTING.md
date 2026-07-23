# Contributing

## Requirements

- PowerShell 7.4+
- Pester 5+

Install the published baseline from PowerShell Gallery:

```powershell
Install-Module TerminalSlides
```

## Workflow

1. Run `./build.ps1` from the repository root
2. Add or update tests with every functional change
3. Keep changes cross-platform and avoid host-specific assumptions

## Style

- Prefer small, composable functions
- Use approved verbs and cmdlet binding for public commands
- Avoid executing untrusted content during import or export
