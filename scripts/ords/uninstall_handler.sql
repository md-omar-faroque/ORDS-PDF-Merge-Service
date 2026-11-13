-- Use only if this handler/template was created specifically for this project.
-- The supplied guide warns that patient_portal.reports / :invoiceNo may pre-exist.
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
