# ORDS PDF Merge Service

Merge invoice-related PDF files from a Linux directory and serve the result through Oracle REST Data Services (ORDS).

This repository packages the workflow described in the supplied implementation guide for:

- Oracle Database 19c with Oracle JVM
- Oracle APEX and ORDS
- Linux database host
- `pdfunite` from Poppler (`/usr/bin/pdfunite`)
- Application schema: `MEDICARE_NEW`
- Oracle directory object: `MY_FILE_ATTACHMENT`
- OS directory: `/mysoft/file_attachment/prescription`

> **Important:** This is a starting implementation based on the supplied guide, not a security-certified patient-document service. The guide explicitly warns that sequential invoice numbers are guessable. Do not expose patient reports publicly until you implement authorization or unguessable, expiring access tokens and test them.

## Request flow

1. A client requests an invoice URL such as `/medicare/medicare/reports/I26009058`.
2. The ORDS GET handler calls `get_invoice_pdf`.
3. The Java stored procedure finds matching PDFs and invokes `pdfunite`.
4. PL/SQL reads the merged file into a BLOB and removes the temporary merged file.
5. ORDS streams the PDF, or returns a friendly not-ready response.

PL/SQL does not merge the PDFs itself. Java invokes the Linux `pdfunite` executable. PDFBox is not used.

## Repository layout

```text
.
├── README.md
├── LICENSE
├── .gitignore
├── docs/
│   ├── IMPLEMENTATION_GUIDE.md
│   └── SECURITY_AND_OPERATIONS.md
├── scripts/
│   ├── linux/
│   │   └── check_environment.sh
│   ├── sql/
│   │   ├── sys/
│   │   │   └── 01_directory_and_java_permissions.sql
│   │   └── app/
│   │       ├── 01_install_pdf_merge.sql
│   │       ├── 02_test_pdf_merge.sql
│   │       └── 99_uninstall_app_objects.sql
│   └── ords/
│       ├── get_invoice_pdf_handler.sql
│       └── uninstall_handler.sql
└── tests/
    └── manual_test_checklist.md
```

## Installation

Run steps in order. Review each script and replace environment-specific values before execution.

### 1. Linux host

As the Oracle OS account, run:

```bash
bash scripts/linux/check_environment.sh
```

Install Poppler utilities as root if `pdfunite` is absent:

```bash
dnf install -y poppler-utils
```

Ensure the target folder exists and the Oracle OS account can read source PDFs and create/delete merged files.

### 2. SYS or DBA

Review and run `scripts/sql/sys/01_directory_and_java_permissions.sql` as a DBA. It creates or replaces the Oracle directory object and grants directory and Java permissions to `MEDICARE_NEW`.

The Java policy grants are broad enough for the configured directory and executable. Keep the directory dedicated to this use case where possible.

### 3. Application schema

Connect as `MEDICARE_NEW` and run:

```sql
@ scripts/sql/app/01_install_pdf_merge.sql
```

The script creates:

- Java source `PdfUniteDir`
- PL/SQL wrapper `PDF_UNITE_DIR`
- `READ_DIR_PDF`
- `GET_INVOICE_PDF`

Reconnect after Java permissions are granted if you encounter a cached Java permission error. If the Java source was just recompiled and the first test reports ORA-29549, retry once as described in the guide.

### 4. Test in SQL

Run:

```sql
@ scripts/sql/app/02_test_pdf_merge.sql
```

Edit the sample invoice number in the test script first.

### 5. ORDS

Create or edit the GET handler for module `patient_portal.reports`, template `:invoiceNo`.

- Method: `GET`
- Source Type: `PL/SQL`
- Bind variable: `:invoiceNo`

Copy the contents of `scripts/ords/get_invoice_pdf_handler.sql` into the handler source. The handler is deliberately provided as a source file rather than an automatic deployment script because ORDS module/template ownership and existing handlers vary by environment.

Example URL:

```text
https://your-host/medicare/medicare/reports/I26009058
```

## Matching and merge order

- Only filenames ending in `.pdf` (case-insensitive) are considered.
- Temporary files whose names start with `merged_` are skipped.
- The invoice number must appear as a whole alphanumeric token, bounded by non-alphanumeric characters or filename edges.
- Matching files are sorted oldest first by file modification time; filename breaks ties.
- If one file matches, it is returned without creating a merged file.
- If multiple files match, `pdfunite` creates a temporary merged PDF.

## Configuration

The sample values are intentionally centralized in the scripts and documentation. Search for these strings before deploying:

- `MEDICARE_NEW`
- `MY_FILE_ATTACHMENT`
- `/mysoft/file_attachment/prescription`
- `/usr/bin/pdfunite`
- `patient_portal.reports`
- `:invoiceNo`

The directory whitelist in `GET_INVOICE_PDF` must be updated if you add another approved directory. Do not accept a directory name directly from a request parameter.

## Security and production readiness

Read [Security and Operations](docs/SECURITY_AND_OPERATIONS.md) before exposing this endpoint.

At minimum:

- Add patient-level authorization or unguessable, expiring access tokens. Invoice numbers alone are not authorization.
- Keep HTTPS enabled.
- Restrict ORDS access and avoid exposing internal exception details.
- Restrict filesystem access to the minimum required directory.
- Add operational monitoring and cleanup for abandoned `merged_*.pdf` files.
- Test concurrency, large PDFs, malformed PDFs, zero-byte PDFs, and process failures.
- Review whether generating a merged file in the source directory is appropriate for your deployment.

## Rollback

1. Restore or remove the ORDS handler carefully. The guide notes that `:invoiceNo` may have existed before this project.
2. Run `scripts/sql/app/99_uninstall_app_objects.sql` as `MEDICARE_NEW`.
3. Revoke only the Java permissions added for this project using the DBA rollback statements in `docs/IMPLEMENTATION_GUIDE.md`.
4. Remove only recognized test and temporary files. Do not delete the shared prescription directory or real application PDFs.

See the implementation guide for the full DBA rollback and Linux cleanup procedures.

## Source guide

The supplied guide has been reorganized into [Implementation Guide](docs/IMPLEMENTATION_GUIDE.md). The repository keeps the original environment assumptions and operational sequence visible.

## License

See [LICENSE](LICENSE). Confirm ownership and third-party notices before publishing this repository publicly.
