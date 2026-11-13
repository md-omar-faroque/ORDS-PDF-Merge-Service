# Security and Operations

## Critical patient-data warning

The sample URL uses a sequential invoice number. The supplied guide explicitly states that anyone who can change the number may be able to retrieve another patient's report. A sequential identifier is not access control.

Before production use, implement an authorization design such as:

- Authenticated patient identity plus server-side ownership check; or
- A cryptographically random, high-entropy, expiring token mapped server-side to one permitted report.

Do not treat an invoice number, patient ID, or other guessable value as a secret. Do not place long-lived bearer tokens in logs or analytics.

## Additional hardening recommendations

These are engineering recommendations beyond the supplied guide and must be implemented and tested for your environment:

1. **ORDS authorization:** protect the route with an appropriate ORDS privilege or perform a server-side authorization check before reading files.
2. **Output escaping:** the current handler inserts fixed title/message strings into HTML. If these become dynamic, HTML-escape them.
3. **Process execution:** Java uses `ProcessBuilder` with a fixed executable path and argument list, avoiding shell-string interpolation. Keep it that way; never pass user-controlled command fragments.
4. **Resource limits:** set operational limits for request duration, number of matching files, individual/combined file size, and concurrent merges. The sample does not implement these limits.
5. **Temporary files:** use a dedicated restricted working directory if possible. Monitor and clean only known `merged_*.pdf` temporary outputs. Do not run broad deletion commands in a directory containing live application documents.
6. **Failure cleanup:** test what happens if the merge succeeds but BLOB loading fails. The sample attempts cleanup after a successful merge/read path but is not a complete crash-recovery mechanism.
7. **Process output:** the sample reads process output before waiting. Test noisy failures and large outputs; consider bounded output capture and robust timeout/termination handling.
8. **PDF validation:** test corrupt, encrypted, zero-byte, unusually large, and adversarial PDFs.
9. **Auditing:** record access decisions and report identifiers without logging patient document contents or bearer tokens.
10. **Transport:** require HTTPS and review reverse-proxy, ORDS, and database logging policies.

## Operational checklist

- `pdfunite` exists at the configured path and is executable by the database OS account.
- The Oracle OS account can read source PDFs and write/delete temporary merged PDFs.
- Oracle JVM is installed and `VALID`.
- Directory grants and Java policy grants are limited to the intended schema and paths.
- Java source and class are `VALID`.
- ORDS handler Source Type is `PL/SQL`.
- The URL template bind name exactly matches `:invoiceNo`.
- No debug `SQLERRM` output is exposed to patients.
- Temporary files are monitored and cleaned safely.
- Authorization has been tested using a different patient's invoice/token.
