# Manual Test Checklist

Use a non-production test directory and synthetic PDFs wherever possible.

## Environment

- [ ] `which pdfunite` resolves to `/usr/bin/pdfunite`.
- [ ] Oracle OS account can read the source directory.
- [ ] Oracle OS account can create and delete a temporary PDF in the directory.
- [ ] Oracle JVM component status is `VALID`.
- [ ] `DBA_JAVA_POLICY` contains the intended grants.
- [ ] Reconnected `MEDICARE_NEW` session after policy changes.

## Matching and merge

- [ ] No matching PDF returns the expected not-ready behavior.
- [ ] One matching PDF is returned without a merge output.
- [ ] Two matching PDFs are merged.
- [ ] Files are ordered oldest first.
- [ ] Equal modification times use filename order.
- [ ] `merged_*.pdf` files are excluded from subsequent matching.
- [ ] Invoice text embedded inside a larger alphanumeric token does not match.
- [ ] Invoice text bounded by punctuation or filename edges does match.
- [ ] Uppercase and lowercase `.pdf` extensions are handled.
- [ ] Zero-byte and damaged PDFs fail safely.
- [ ] A merge failure does not expose internal details to the caller.
- [ ] Temporary output is removed after a successful request.

## ORDS

- [ ] Handler method is GET.
- [ ] Handler Source Type is PL/SQL, not Media Resource.
- [ ] Handler bind variable spelling/case matches `:invoiceNo`.
- [ ] Valid test invoice returns `application/pdf`.
- [ ] Missing invoice returns the friendly not-ready page.
- [ ] Unexpected server error returns a generic page.
- [ ] Internal SQL errors are not exposed.

## Security / concurrency

- [ ] Unauthorized user cannot access another patient's report.
- [ ] Sequential invoice enumeration is blocked by authorization/token design.
- [ ] Concurrent requests for the same invoice do not collide.
- [ ] Concurrent requests for different invoices do not collide.
- [ ] Large reports and request timeouts are tested.
- [ ] Temporary-file cleanup after interrupted requests is tested.
