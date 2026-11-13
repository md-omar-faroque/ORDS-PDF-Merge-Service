# Final Guide: Merge PDFs from a Directory and Serve Them with ORDS

Environment: Oracle Database 19c, Linux server, APEX and ORDS. Application schema `MEDICARE_NEW`, directory object `MY_FILE_ATTACHMENT` (OS path `/mysoft/file_attachment/prescription`).

## 1. How it works

```
Patient opens  https://apex24.myhealthbd.com/medicare/medicare/reports/I26009058
  -> ORDS PL/SQL handler calls get_invoice_pdf('MY_FILE_ATTACHMENT', invoice)
  -> pdf_unite_dir (Java stored procedure) finds every PDF whose name contains the invoice no.
  -> runs /usr/bin/pdfunite on the Linux server and writes merged_xxx.pdf
  -> read_dir_pdf loads the merged file as a BLOB, the temp file is deleted
  -> ORDS returns the PDF, or a friendly 'Report not ready' page if no file exists
```

Plain PL/SQL cannot merge PDFs, so a small Java stored procedure calls the OS tool `pdfunite`. PDFBox is not used.

## 2. Names used in this guide

| Item | Value |
| --- | --- |
| Application schema | MEDICARE\_NEW |
| Directory object | MY\_FILE\_ATTACHMENT |
| OS folder | /mysoft/file\_attachment/prescription |
| Merge tool | /usr/bin/pdfunite |
| ORDS module and template | patient\_portal.reports, template :invoiceNo |
| Database connection | localhost:2115/orclpdb1 |

Replace these values if your environment differs.

## 3. Part 1: Linux commands (PuTTY, on the database server)

**Step 1.1. Log in and switch to the oracle user**

```bash
su - oracle
```

**Step 1.2. Check that pdfunite exists**

```bash
which pdfunite
```

Expected output: `/usr/bin/pdfunite`. If it is missing, install it as root:

```bash
dnf install -y poppler-utils
```

**Step 1.3. Check the PDF folder and its permissions**

```bash
ls -ld /mysoft/file_attachment/prescription
```

The folder must be owned by `oracle`, or be readable and writable by the oracle user. If it is not, run as root:

```bash
chown oracle:oracle /mysoft/file_attachment/prescription
chmod 755 /mysoft/file_attachment/prescription
```

To create a new folder for a new directory object:

```bash
mkdir -p /path/to/new_folder
chown oracle:oracle /path/to/new_folder
```

**Step 1.4. Find the PDF files of one invoice**

```bash
ls -l /mysoft/file_attachment/prescription | grep I26009058
```

All PDFs whose name contains the invoice number as a separate token will be merged, so remove old test files you do not want in the result.

**Step 1.5. Test the merge by hand**

```bash
cd /mysoft/file_attachment/prescription
pdfunite file1.pdf file2.pdf /tmp/test_merged.pdf
ls -l /tmp/test_merged.pdf
rm /tmp/test_merged.pdf
```

The merged size should be about the sum of the inputs. If this works, the OS side is ready.

**Step 1.6. Find the Oracle service name (only if needed for sqlplus tests)**

```bash
lsnrctl status
```

## 4. Part 2: Statements for SYS (or a DBA user)

Run these in Toad as script (F5).

**Step 2.1. Check that Oracle JVM is installed**

```sql
SELECT comp_name, status FROM dba_registry WHERE comp_id = 'JAVAVM';
```

The status must be `VALID`. Without Oracle JVM the Java procedure cannot be created.

**Step 2.2. Directory object and access for the application schema**

```sql
CREATE OR REPLACE DIRECTORY MY_FILE_ATTACHMENT AS '/mysoft/file_attachment/prescription';
GRANT READ, WRITE ON DIRECTORY MY_FILE_ATTACHMENT TO MEDICARE_NEW;
```

Skip the first line if the directory object already exists. WRITE is needed so the temporary merged file can be deleted.

**Step 2.3. Java permissions for the application schema**

```sql
BEGIN
  DBMS_JAVA.GRANT_PERMISSION('MEDICARE_NEW','SYS:java.io.FilePermission','/mysoft/file_attachment/prescription','read');
  DBMS_JAVA.GRANT_PERMISSION('MEDICARE_NEW','SYS:java.io.FilePermission','/mysoft/file_attachment/prescription/-','read,write,delete');
  DBMS_JAVA.GRANT_PERMISSION('MEDICARE_NEW','SYS:java.io.FilePermission','/usr/bin/pdfunite','execute');
  DBMS_JAVA.GRANT_PERMISSION('MEDICARE_NEW','SYS:java.lang.RuntimePermission','readFileDescriptor','');
  DBMS_JAVA.GRANT_PERMISSION('MEDICARE_NEW','SYS:java.lang.RuntimePermission','writeFileDescriptor','');
END;
/
COMMIT;
```

Check the grants:

```sql
SELECT kind, grantee, type_name, name, action
  FROM dba_java_policy
 WHERE grantee = 'MEDICARE_NEW';
```

After granting, disconnect and reconnect the MEDICARE\_NEW session, because Java permissions are cached per session.

**Step 2.4. For every additional directory (optional)**

```sql
CREATE OR REPLACE DIRECTORY MY_OTHER_DIR AS '/path/to/other_dir';
GRANT READ, WRITE ON DIRECTORY MY_OTHER_DIR TO MEDICARE_NEW;

BEGIN
  DBMS_JAVA.GRANT_PERMISSION('MEDICARE_NEW','SYS:java.io.FilePermission','/path/to/other_dir','read');
  DBMS_JAVA.GRANT_PERMISSION('MEDICARE_NEW','SYS:java.io.FilePermission','/path/to/other_dir/-','read,write,delete');
END;
/
```

Also complete Step 1.3 for the new folder on Linux.

## 5. Part 3: Statements for the application schema (MEDICARE\_NEW)

Run these in Toad as script (F5). Put `SET DEFINE OFF` at the top so the `&&` characters in the Java code are not stripped.

**Step 3.1. Java source and PL/SQL wrapper**

The invoice number is matched as a whole token anywhere in the file name, for example `Test_I26009058_20261110_153205.pdf` or `I26009058_xxx.pdf`. Files are merged oldest first by file date. Temporary `merged_*` files are skipped.

```sql
SET DEFINE OFF

CREATE OR REPLACE AND COMPILE JAVA SOURCE NAMED "PdfUniteDir" AS
import java.io.*;
import java.util.*;

public class PdfUniteDir {

    static boolean hasInvoice(String name, String inv) {
        int from = 0;
        while (true) {
            int i = name.indexOf(inv, from);
            if (i < 0) return false;
            boolean leftOk = true;
            boolean rightOk = true;
            if (i > 0) {
                leftOk = !Character.isLetterOrDigit(name.charAt(i - 1));
            }
            int e = i + inv.length();
            if (e < name.length()) {
                rightOk = !Character.isLetterOrDigit(name.charAt(e));
            }
            if (leftOk) { if (rightOk) { return true; } }
            from = i + 1;
        }
    }

    public static String run(String dir, String prefix, String output) throws Exception {
        File[] all = new File(dir).listFiles();
        List<File> files = new ArrayList<File>();
        if (all != null) {
            for (int i = 0; i < all.length; i++) {
                String n = all[i].getName();
                boolean isPdf = n.toLowerCase().endsWith(".pdf");
                boolean isTemp = n.startsWith("merged_");
                if (isPdf) { if (!isTemp) { if (hasInvoice(n, prefix)) { files.add(all[i]); } } }
            }
        }
        Collections.sort(files, new Comparator<File>() {
            public int compare(File a, File b) {
                long x = a.lastModified();
                long y = b.lastModified();
                if (x < y) return -1;
                if (x > y) return 1;
                return a.getName().compareTo(b.getName());
            }
        });
        if (files.size() == 0) return "ERROR: no files found for " + prefix;
        if (files.size() == 1) return "ONE|" + files.get(0).getName();

        List<String> cmd = new ArrayList<String>();
        cmd.add("/usr/bin/pdfunite");
        for (int i = 0; i < files.size(); i++) cmd.add(files.get(i).getPath());
        cmd.add(dir + "/" + output);

        ProcessBuilder pb = new ProcessBuilder(cmd);
        pb.redirectErrorStream(true);
        Process p = pb.start();
        StringBuilder sb = new StringBuilder();
        BufferedReader r = new BufferedReader(new InputStreamReader(p.getInputStream()));
        String line;
        while ((line = r.readLine()) != null) sb.append(line).append('\n');
        int rc = p.waitFor();
        return rc == 0 ? "OK" : "ERROR(" + rc + "): " + sb;
    }
}
/

CREATE OR REPLACE FUNCTION pdf_unite_dir (p_dir VARCHAR2, p_prefix VARCHAR2, p_output VARCHAR2)
RETURN VARCHAR2
AS LANGUAGE JAVA
NAME 'PdfUniteDir.run(java.lang.String, java.lang.String, java.lang.String) return java.lang.String';
/
```

**Step 3.2. Verify the Java objects**

```sql
SELECT object_name, object_type, status
  FROM user_objects
 WHERE object_name LIKE 'PdfUniteDir%';
```

Both the JAVA SOURCE and the JAVA CLASS must be `VALID`. If not, open Schema Browser, Java Sources, PdfUniteDir, Errors tab.

**Step 3.3. Function that reads a file from a directory as BLOB**

```sql
CREATE OR REPLACE FUNCTION read_dir_pdf (p_dir IN VARCHAR2, p_file IN VARCHAR2) RETURN BLOB IS
    l_bfile BFILE := BFILENAME(p_dir, p_file);
    l_blob  BLOB;
    l_dest  INTEGER := 1;
    l_src   INTEGER := 1;
BEGIN
    DBMS_LOB.FILEOPEN(l_bfile, DBMS_LOB.FILE_READONLY);
    DBMS_LOB.CREATETEMPORARY(l_blob, TRUE);
    DBMS_LOB.LOADBLOBFROMFILE(l_blob, l_bfile, DBMS_LOB.GETLENGTH(l_bfile), l_dest, l_src);
    DBMS_LOB.FILECLOSE(l_bfile);
    RETURN l_blob;
EXCEPTION
    WHEN OTHERS THEN
        IF DBMS_LOB.FILEISOPEN(l_bfile) = 1 THEN DBMS_LOB.FILECLOSE(l_bfile); END IF;
        RAISE;
END;
/
```

**Step 3.4. Main function: directory name and invoice number in, merged PDF out**

The whitelist stops callers from reading any directory other than the allowed ones. Add every allowed directory to the list.

```sql
CREATE OR REPLACE FUNCTION get_invoice_pdf (p_dir_name IN VARCHAR2, p_invoice IN VARCHAR2) RETURN BLOB IS
    l_path    VARCHAR2(4000);
    l_out     VARCHAR2(255) := 'merged_' || RAWTOHEX(SYS_GUID()) || '.pdf';
    l_result  VARCHAR2(4000);
    l_blob    BLOB;
BEGIN
    IF p_invoice IS NULL OR NOT REGEXP_LIKE(p_invoice, '^[A-Za-z0-9]+$') THEN
        raise_application_error(-20001, 'Invalid invoice');
    END IF;

    IF p_dir_name NOT IN ('MY_FILE_ATTACHMENT') THEN
        raise_application_error(-20002, 'Directory not allowed');
    END IF;

    SELECT RTRIM(directory_path, '/') INTO l_path
      FROM all_directories WHERE directory_name = p_dir_name;

    l_result := pdf_unite_dir(l_path, p_invoice, l_out);

    IF l_result = 'OK' THEN
        l_blob := read_dir_pdf(p_dir_name, l_out);
        BEGIN
            UTL_FILE.FREMOVE(p_dir_name, l_out);
        EXCEPTION WHEN OTHERS THEN NULL;
        END;
    ELSIF l_result LIKE 'ONE|%' THEN
        l_blob := read_dir_pdf(p_dir_name, SUBSTR(l_result, 5));
    ELSE
        raise_application_error(-20010, l_result);
    END IF;
    RETURN l_blob;
END;
/
```

A standalone function cannot be overloaded, so this replaces any older one-argument version. Every caller must pass two arguments.

**Step 3.5. Test in Toad**

```sql
SELECT DBMS_LOB.GETLENGTH(get_invoice_pdf('MY_FILE_ATTACHMENT', 'I26009058')) FROM dual;
```

A number is the merged PDF size in bytes, so the merge works. If you see `ORA-29549 ... Java session state cleared`, run the statement again, because the class was just recompiled.

## 6. Part 4: ORDS handler (shows a friendly page when no report exists)

In APEX, go to SQL Workshop, RESTful Services, Modules, `patient_portal.reports`, open the template and its GET handler, and set:

- Method: GET
- Source Type: **PL/SQL** (not Media Resource)
- Source: the code below

The bind variable name must match the template parameter exactly, including capital letters. For the template `:invoiceNo` the bind is `:invoiceNo`.

```sql
DECLARE
    l_blob BLOB;

    PROCEDURE show_msg (p_status PLS_INTEGER, p_reason VARCHAR2,
                        p_title VARCHAR2, p_text VARCHAR2) IS
    BEGIN
        owa_util.status_line(p_status, p_reason, FALSE);
        owa_util.mime_header('text/html; charset=utf-8', FALSE);
        owa_util.http_header_close;
        htp.p('<!DOCTYPE html><html><head><meta charset="utf-8">'
           || '<meta name="viewport" content="width=device-width, initial-scale=1">'
           || '<title>' || p_title || '</title>'
           || '<style>body{font-family:Arial,sans-serif;background:#f4f6f8;margin:0;'
           || 'display:flex;align-items:center;justify-content:center;min-height:100vh}'
           || '.box{background:#fff;padding:32px 40px;border-radius:8px;max-width:420px;'
           || 'text-align:center;box-shadow:0 2px 8px rgba(0,0,0,.12)}'
           || 'h2{margin:0 0 12px;color:#1a3c6e}p{margin:0;color:#444;line-height:1.5}'
           || '</style></head><body><div class="box"><h2>' || p_title || '</h2><p>'
           || p_text || '</p></div></body></html>');
    END;
BEGIN
    l_blob := get_invoice_pdf('MY_FILE_ATTACHMENT', :invoiceNo);

    IF l_blob IS NULL OR DBMS_LOB.GETLENGTH(l_blob) = 0 THEN
        show_msg(404, 'Not Found', 'Report not ready',
                 'Your report is not ready yet. Please try again later or contact the hospital.');
    ELSE
        owa_util.mime_header('application/pdf', FALSE);
        htp.p('Content-Length: ' || DBMS_LOB.GETLENGTH(l_blob));
        htp.p('Content-Disposition: inline; filename="report.pdf"');
        owa_util.http_header_close;
        wpg_docload.download_file(l_blob);
    END IF;
EXCEPTION
    WHEN OTHERS THEN
        IF SQLERRM LIKE '%no files found%' THEN
            show_msg(404, 'Not Found', 'Report not ready',
                     'Your report is not ready yet. Please try again later or contact the hospital.');
        ELSE
            show_msg(500, 'Internal Server Error', 'Report unavailable',
                     'We could not load your report right now. Please try again later.');
        END IF;
END;
```

For debugging only, replace the last message with `htf.escape_sc(SQLERRM)` to see the real Oracle error, and change it back before giving links to patients.

**Public URL (no colon, real invoice number):**

```
https://apex24.myhealthbd.com/medicare/medicare/reports/I26009058
```

URL parts: `/medicare/` is the ORDS context path, the second `medicare` is the schema alias, `/reports/` is the module base path, then the invoice number in place of `:invoiceNo`.

If you want a separate path such as `pathologyIbf/I26009058` and do not want to change the existing `:invoiceNo` template, create a new template with the pattern `pathologyIbf/:invoiceNo` in the same module and use the same handler code.

## 7. Test checklist

1. `which pdfunite` prints a path (Step 1.2).
2. Manual `pdfunite` test creates a merged file (Step 1.5).
3. `DBA_JAVA_POLICY` shows the grants and the MEDICARE\_NEW session was reconnected (Step 2.3).
4. `PdfUniteDir` source and class are VALID (Step 3.2).
5. `get_invoice_pdf` returns a size in Toad (Step 3.5).
6. The ORDS URL with a real invoice opens the merged PDF.
7. The ORDS URL with an invoice that has no files shows the Report not ready page.

## 8. Troubleshooting

| Symptom | Cause and fix |
| --- | --- |
| AccessControlException ... has not been granted | Run the dbms\_java.grant\_permission line shown in the message as SYS, then reconnect and retry. |
| ORA-29549 class has changed | The class was recompiled. Run the statement again. |
| ORA-20001 Invalid invoice | The bind is empty or has unexpected characters. Check that the bind name matches the template parameter exactly, for example :invoiceNo. |
| ORA-20002 Directory not allowed | Add the directory name to the whitelist in get\_invoice\_pdf. |
| ORA-20010 ERROR: no files found | No PDF name contains the invoice number as a separate token. Check with the grep command in Step 1.4. |
| ORA-20010 ERROR(1) from pdfunite | One matched PDF is damaged or 0 bytes. Remove or replace that file. |
| ORA-06502 inside SYS.OWA\_UTIL or SYS.HTP | The handler Source Type is Media Resource. Change it to PL/SQL. |
| ORDS error page 555 or 404 | The module, template, method or letter case does not match the URL. List them with the query below. |
| Report unavailable page for a valid invoice | Temporarily show SQLERRM in the handler to see the real error. |
| Java compile error | Run SET DEFINE OFF first, then check Schema Browser, Java Sources, Errors. |

List the ORDS services:

```sql
SELECT m.uri_prefix, t.uri_template, h.method, h.source_type
  FROM user_ords_modules m
  JOIN user_ords_templates t ON t.module_id = m.id
  JOIN user_ords_handlers h ON h.template_id = t.id;
```

## 9. Maintenance and security

Remove leftover temporary merged files (created only if a request failed midway):

```bash
ls -l /mysoft/file_attachment/prescription/merged_*.pdf
rm -f /mysoft/file_attachment/prescription/merged_*.pdf
```

Security notes:

- Invoice numbers are sequential and guessable. Anyone who changes the number in the URL can open another patient's report. For real patient data, add a random token to the file name or URL and look it up, and keep HTTPS on.
- All PDFs whose name contains the invoice number are merged, including old test files. Keep only the files that belong in the report.
- Never pass the directory name from the URL. It is hard-coded in the handler and checked by the whitelist.
- Do not leave the debug message in the handler. It exposes technical details.
- Change the database and OS passwords that were shared during setup, and clear the shell history with `history -c`.
- The earlier PDFBox and BouncyCastle attempt is not part of this solution. If those jars were loaded with loadjava, remove them with dropjava as described in the first guide, section 7.

## 10. Undo everything (rollback scripts)

Run the parts in this order: ORDS first, then the application schema, then SYS, then Linux. Read each warning before running a script. Nothing here touches your other application files.

**Do not remove these, they existed before this project:**

- The directory object `MY_FILE_ATTACHMENT` and the folder `/mysoft/file_attachment/prescription`. Other parts of the application store files there.
- The procedure `PD_BLOB_TO_FILE_DIR` and the other ORDS modules and templates.
- All PDF files that do not belong to this test (prescriptions, CVs and so on).

### 10.1 ORDS (as MEDICARE\_NEW)

Warning: the template `:invoiceNo` already had a GET handler before this project. Deleting it removes that original service. If anything else uses it, do not delete it. Instead open the handler in APEX (SQL Workshop, RESTful Services, patient\_portal.reports, :invoiceNo, GET) and restore its original Source Type and source code.

If you want to delete the handler and template:

```sql
BEGIN
    ORDS.DELETE_HANDLER(
        p_module_name => 'patient_portal.reports',
        p_pattern     => ':invoiceNo',
        p_method      => 'GET');
    ORDS.DELETE_TEMPLATE(
        p_module_name => 'patient_portal.reports',
        p_pattern     => ':invoiceNo');
    COMMIT;
END;
/
```

If you also created the separate template `pathologyIbf/:invoiceNo`, delete it. Use the module name where you created it, for example `patient_portal.reports` or `reports`:

```sql
BEGIN
    ORDS.DELETE_HANDLER(
        p_module_name => 'patient_portal.reports',
        p_pattern     => 'pathologyIbf/:invoiceNo',
        p_method      => 'GET');
    ORDS.DELETE_TEMPLATE(
        p_module_name => 'patient_portal.reports',
        p_pattern     => 'pathologyIbf/:invoiceNo');
    COMMIT;
END;
/
```

If an earlier test created a module named `reports` that you no longer need, remove it:

```sql
BEGIN
    ORDS.DELETE_MODULE(p_module_name => 'reports');
    COMMIT;
END;
/
```

Templates named `pathologyIbf/:invoice_no` or `consultationinvoice/:invoice_no` from earlier tests are deleted the same way, with their own pattern.

### 10.2 Application schema objects (as MEDICARE\_NEW)

```sql
DROP FUNCTION get_invoice_pdf;
DROP FUNCTION read_dir_pdf;
DROP FUNCTION pdf_unite_dir;
DROP JAVA SOURCE "PdfUniteDir";
```

Dropping the Java source also removes its compiled class. If any statement says the object does not exist, ignore it and continue.

Remove older objects from earlier attempts, only if they exist. This block ignores objects that are missing:

```sql
BEGIN
    FOR r IN (SELECT object_name FROM user_objects
               WHERE object_type = 'FUNCTION'
                 AND object_name IN ('PDF_MERGE2', 'PDF_UNITE'))
    LOOP
        EXECUTE IMMEDIATE 'DROP FUNCTION ' || r.object_name;
    END LOOP;

    FOR r IN (SELECT object_name FROM user_objects
               WHERE object_type = 'JAVA SOURCE'
                 AND object_name IN ('PdfMerge', 'PdfUnite'))
    LOOP
        EXECUTE IMMEDIATE 'DROP JAVA SOURCE "' || r.object_name || '"';
    END LOOP;

    BEGIN
        DBMS_SCHEDULER.DROP_JOB('TEST_PDFUNITE', TRUE);
    EXCEPTION WHEN OTHERS THEN NULL;
    END;

    BEGIN
        DBMS_CREDENTIAL.DROP_CREDENTIAL('OS_CRED', TRUE);
    EXCEPTION WHEN OTHERS THEN NULL;
    END;
END;
/
```

The `report_file_log` table is only needed if you created it in an earlier design. Drop it only if you are sure nothing else uses it:

```sql
-- DROP TABLE report_file_log PURGE;
```

### 10.3 SYS or DBA statements

Remove the Java permissions that were granted to the application schema. Use the same values that were used to grant them.

```sql
BEGIN
  DBMS_JAVA.REVOKE_PERMISSION('MEDICARE_NEW','SYS:java.io.FilePermission','/mysoft/file_attachment/prescription','read');
  DBMS_JAVA.REVOKE_PERMISSION('MEDICARE_NEW','SYS:java.io.FilePermission','/mysoft/file_attachment/prescription/-','read,write,delete');
  DBMS_JAVA.REVOKE_PERMISSION('MEDICARE_NEW','SYS:java.io.FilePermission','/usr/bin/pdfunite','execute');
  DBMS_JAVA.REVOKE_PERMISSION('MEDICARE_NEW','SYS:java.lang.RuntimePermission','readFileDescriptor','');
  DBMS_JAVA.REVOKE_PERMISSION('MEDICARE_NEW','SYS:java.lang.RuntimePermission','writeFileDescriptor','');
END;
/
COMMIT;
```

If you gave permissions for other directories (Step 2.4), revoke those paths the same way.

Check that nothing is left:

```sql
SELECT kind, grantee, type_name, name, action
  FROM dba_java_policy
 WHERE grantee = 'MEDICARE_NEW';
```

The directory object is normally kept, because the application uses it. Run these only if `MY_FILE_ATTACHMENT` was created just for this project and nothing else uses it:

```sql
-- REVOKE READ, WRITE ON DIRECTORY MY_FILE_ATTACHMENT FROM MEDICARE_NEW;
-- DROP DIRECTORY MY_FILE_ATTACHMENT;
```

If you created `MY_OTHER_DIR` in Step 2.4 for a test, remove it:

```sql
-- DROP DIRECTORY MY_OTHER_DIR;
```

### 10.4 Remove the PDFBox and BouncyCastle attempt (only if you loaded it)

If you ran `loadjava` earlier, remove those classes (as the oracle user on Linux, from the folder that holds each jar). Replace USER/PASSWORD:

```bash
cd /tmp/pdfjars
dropjava -v -thin -user USER/PASSWORD@localhost:2115/orclpdb1 pdfbox-2.0.30.jar fontbox-2.0.30.jar commons-logging-1.2.jar

cd /tmp/bcjars
dropjava -v -thin -user USER/PASSWORD@localhost:2115/orclpdb1 bcprov-jdk15on-1.70.jar bcpkix-jdk15on-1.70.jar
```

Check what is left in the schema (as MEDICARE\_NEW):

```sql
SELECT object_type, COUNT(*) FROM user_objects
 WHERE object_type LIKE 'JAVA%'
 GROUP BY object_type;
```

The result should be empty, or contain only Java objects that belong to something else.

### 10.5 Linux cleanup (PuTTY)

Temporary files, jars and logs:

```bash
rm -f /mysoft/file_attachment/prescription/merged_*.pdf
rm -f /tmp/test_merged.pdf
rm -f /tmp/load.log /tmp/load2.log /tmp/load_bc.log
rm -rf /tmp/pdfjars /tmp/bcjars
```

If `rm` says permission denied for `/tmp/pdfjars`, run that line as root.

Test PDFs created during setup. List them first, then delete only what you recognize as test files:

```bash
ls -l /mysoft/file_attachment/prescription | grep -E 'Test_|I26009058|merged_'
```

Then delete them one by one by name, or with a narrow pattern:

```bash
rm -f /mysoft/file_attachment/prescription/Test_*.pdf
rm -f /mysoft/file_attachment/prescription/merged_test.pdf
```

Do not run `rm *.pdf` in that folder. It holds real files from the application.

The `pdfunite` tool belongs to the poppler-utils package. Leave it installed if anything else uses it. To remove it (as root):

```bash
dnf remove -y poppler-utils
```

Finally, clear the shell history, because it contains database passwords:

```bash
history -c
```

### 10.6 Final check that everything is gone

As MEDICARE\_NEW:

```sql
SELECT object_name, object_type FROM user_objects
 WHERE object_name IN ('GET_INVOICE_PDF','READ_DIR_PDF','PDF_UNITE_DIR','PdfUniteDir','PDF_MERGE2','PdfMerge');
```

No rows should be returned. Then open the ORDS URL. It should now fail or return the original behaviour of the template, depending on what you kept in Step 10.1.
