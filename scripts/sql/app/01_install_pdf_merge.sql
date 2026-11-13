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
            if (leftOk && rightOk) return true;
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
                if (isPdf && !isTemp && hasInvoice(n, prefix)) {
                    files.add(all[i]);
                }
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
        while ((line = r.readLine()) != null) sb.append(line).append('\\n');
        int rc = p.waitFor();
        return rc == 0 ? "OK" : "ERROR(" + rc + "): " + sb;
    }
}
/

CREATE OR REPLACE FUNCTION pdf_unite_dir (
    p_dir    VARCHAR2,
    p_prefix VARCHAR2,
    p_output VARCHAR2
) RETURN VARCHAR2
AS LANGUAGE JAVA
NAME 'PdfUniteDir.run(java.lang.String, java.lang.String, java.lang.String) return java.lang.String';
/

CREATE OR REPLACE FUNCTION read_dir_pdf (
    p_dir  IN VARCHAR2,
    p_file IN VARCHAR2
) RETURN BLOB
IS
    l_bfile BFILE := BFILENAME(p_dir, p_file);
    l_blob  BLOB;
    l_dest  INTEGER := 1;
    l_src   INTEGER := 1;
BEGIN
    DBMS_LOB.FILEOPEN(l_bfile, DBMS_LOB.FILE_READONLY);
    DBMS_LOB.CREATETEMPORARY(l_blob, TRUE);
    DBMS_LOB.LOADBLOBFROMFILE(
        l_blob, l_bfile, DBMS_LOB.GETLENGTH(l_bfile), l_dest, l_src);
    DBMS_LOB.FILECLOSE(l_bfile);
    RETURN l_blob;
EXCEPTION
    WHEN OTHERS THEN
        IF DBMS_LOB.FILEISOPEN(l_bfile) = 1 THEN
            DBMS_LOB.FILECLOSE(l_bfile);
        END IF;
        RAISE;
END;
/

CREATE OR REPLACE FUNCTION get_invoice_pdf (
    p_dir_name IN VARCHAR2,
    p_invoice  IN VARCHAR2
) RETURN BLOB
IS
    l_path   VARCHAR2(4000);
    l_out    VARCHAR2(255) := 'merged_' || RAWTOHEX(SYS_GUID()) || '.pdf';
    l_result VARCHAR2(4000);
    l_blob   BLOB;
BEGIN
    IF p_invoice IS NULL OR NOT REGEXP_LIKE(p_invoice, '^[A-Za-z0-9]+$') THEN
        RAISE_APPLICATION_ERROR(-20001, 'Invalid invoice');
    END IF;

    IF p_dir_name NOT IN ('MY_FILE_ATTACHMENT') THEN
        RAISE_APPLICATION_ERROR(-20002, 'Directory not allowed');
    END IF;

    SELECT RTRIM(directory_path, '/')
      INTO l_path
      FROM all_directories
     WHERE directory_name = p_dir_name;

    l_result := pdf_unite_dir(l_path, p_invoice, l_out);

    IF l_result = 'OK' THEN
        l_blob := read_dir_pdf(p_dir_name, l_out);
        BEGIN
            UTL_FILE.FREMOVE(p_dir_name, l_out);
        EXCEPTION
            WHEN OTHERS THEN NULL;
        END;
    ELSIF l_result LIKE 'ONE|%' THEN
        l_blob := read_dir_pdf(p_dir_name, SUBSTR(l_result, 5));
    ELSE
        RAISE_APPLICATION_ERROR(-20010, l_result);
    END IF;

    RETURN l_blob;
END;
/
