-- Run as SYS or a DBA with the required privileges.
-- Review the OS path and schema before running.
CREATE OR REPLACE DIRECTORY MY_FILE_ATTACHMENT
  AS '/mysoft/file_attachment/prescription';

GRANT READ, WRITE ON DIRECTORY MY_FILE_ATTACHMENT TO MEDICARE_NEW;

BEGIN
  DBMS_JAVA.GRANT_PERMISSION(
    'MEDICARE_NEW', 'SYS:java.io.FilePermission',
    '/mysoft/file_attachment/prescription', 'read');
  DBMS_JAVA.GRANT_PERMISSION(
    'MEDICARE_NEW', 'SYS:java.io.FilePermission',
    '/mysoft/file_attachment/prescription/-', 'read,write,delete');
  DBMS_JAVA.GRANT_PERMISSION(
    'MEDICARE_NEW', 'SYS:java.io.FilePermission',
    '/usr/bin/pdfunite', 'execute');
  DBMS_JAVA.GRANT_PERMISSION(
    'MEDICARE_NEW', 'SYS:java.lang.RuntimePermission',
    'readFileDescriptor', '');
  DBMS_JAVA.GRANT_PERMISSION(
    'MEDICARE_NEW', 'SYS:java.lang.RuntimePermission',
    'writeFileDescriptor', '');
END;
/
COMMIT;

-- Verify:
SELECT kind, grantee, type_name, name, action
  FROM dba_java_policy
 WHERE grantee = 'MEDICARE_NEW';
