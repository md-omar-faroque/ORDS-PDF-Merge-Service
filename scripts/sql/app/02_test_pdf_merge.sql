-- Change the invoice number to one that has PDF files in the configured directory.
SELECT DBMS_LOB.GETLENGTH(
         get_invoice_pdf('MY_FILE_ATTACHMENT', 'I26009058')
       ) AS pdf_size_bytes
  FROM dual;
