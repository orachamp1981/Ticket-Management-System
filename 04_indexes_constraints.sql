CREATE UNIQUE INDEX ux_tms_uo_primary
ON tms_user_organizations (
  CASE WHEN is_primary = 'Y' THEN user_id END
);

CREATE INDEX ix_ticket_org_status ON tms_tickets(org_id, status);
CREATE INDEX ix_ticket_org_category ON tms_tickets(org_id, category_id);
CREATE INDEX ix_ticket_assignee ON tms_tickets(assigned_user_id);
CREATE INDEX ix_comment_ticket ON tms_ticket_comments(ticket_id);
CREATE INDEX ix_history_ticket ON tms_ticket_history(ticket_id);
CREATE INDEX ix_audit_table_pk ON tms_audit_log(table_name, pk_value);

CREATE OR REPLACE TRIGGER trg_tms_membership_dept_chk
BEFORE INSERT OR UPDATE OF org_id, department_id ON tms_user_organizations
FOR EACH ROW
DECLARE
  l_org_id tms_departments.org_id%TYPE;
BEGIN
  IF :NEW.department_id IS NOT NULL THEN
    SELECT org_id INTO l_org_id
      FROM tms_departments
     WHERE department_id = :NEW.department_id;

    IF l_org_id <> :NEW.org_id THEN
      RAISE_APPLICATION_ERROR(-20001,'Department must belong to the selected organization.');
    END IF;
  END IF;
END;
/
