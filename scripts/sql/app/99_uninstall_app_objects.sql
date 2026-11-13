-- Run as MEDICARE_NEW.
-- WARNING: dropping GET_INVOICE_PDF may affect other callers.
DROP FUNCTION get_invoice_pdf;
DROP FUNCTION read_dir_pdf;
DROP FUNCTION pdf_unite_dir;
DROP JAVA SOURCE "PdfUniteDir";

-- Check for remaining project objects:
SELECT object_name, object_type
  FROM user_objects
 WHERE object_name IN (
   'GET_INVOICE_PDF', 'READ_DIR_PDF', 'PDF_UNITE_DIR', 'PdfUniteDir'
 );
