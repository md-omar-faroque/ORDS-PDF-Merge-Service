DECLARE
    l_blob BLOB;

    PROCEDURE show_msg (
        p_status PLS_INTEGER,
        p_reason VARCHAR2,
        p_title  VARCHAR2,
        p_text   VARCHAR2
    ) IS
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
