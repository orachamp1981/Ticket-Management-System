/*
Foundation placeholder.
Blueprint v1.5 requires PKG_TMS_AUDIT.LOG_CHANGE as the frozen central audit engine.
Install the hand-built PKG_TMS_AUDIT before enabling production audit triggers.
*/
CREATE OR REPLACE TRIGGER trg_tms_tickets_audit
AFTER INSERT OR UPDATE OR DELETE ON tms_tickets
FOR EACH ROW
BEGIN
  NULL;
  -- Replace NULL with frozen PKG_TMS_AUDIT.LOG_CHANGE call.
END;
/
