CREATE OR REPLACE PACKAGE pkg_tms_ticket AS
  PROCEDURE validate_ticket(
    p_org_id       IN NUMBER,
    p_category_id  IN NUMBER,
    p_priority     IN VARCHAR2,
    p_subject      IN VARCHAR2
  );

  PROCEDURE create_ticket(
    p_org_id       IN NUMBER,
    p_category_id  IN NUMBER,
    p_subject      IN VARCHAR2,
    p_description  IN CLOB,
    p_priority     IN VARCHAR2,
    p_requester_user_id IN NUMBER,
    p_ticket_id    OUT NUMBER
  );

  PROCEDURE change_status(
    p_ticket_id    IN NUMBER,
    p_new_status   IN VARCHAR2,
    p_comment      IN VARCHAR2 DEFAULT NULL
  );
END pkg_tms_ticket;
/

CREATE OR REPLACE PACKAGE BODY pkg_tms_ticket AS

  PROCEDURE validate_ticket(
    p_org_id IN NUMBER,
    p_category_id IN NUMBER,
    p_priority IN VARCHAR2,
    p_subject IN VARCHAR2
  ) IS
    l_count NUMBER;
  BEGIN
    IF TRIM(p_subject) IS NULL THEN
      RAISE_APPLICATION_ERROR(-20010,'Ticket subject is required.');
    END IF;

    IF p_priority NOT IN ('CRITICAL','HIGH','MEDIUM','LOW') THEN
      RAISE_APPLICATION_ERROR(-20011,'Invalid ticket priority.');
    END IF;

    SELECT COUNT(*)
      INTO l_count
      FROM tms_categories
     WHERE category_id = p_category_id
       AND status = 'ACTIVE'
       AND (org_id IS NULL OR org_id = p_org_id);

    IF l_count = 0 THEN
      RAISE_APPLICATION_ERROR(-20012,'Category is not available for this organization.');
    END IF;
  END;

  PROCEDURE create_ticket(
    p_org_id IN NUMBER,
    p_category_id IN NUMBER,
    p_subject IN VARCHAR2,
    p_description IN CLOB,
    p_priority IN VARCHAR2,
    p_requester_user_id IN NUMBER,
    p_ticket_id OUT NUMBER
  ) IS
    l_org_code tms_organizations.org_code%TYPE;
  BEGIN
    validate_ticket(p_org_id,p_category_id,p_priority,p_subject);

    SELECT org_code INTO l_org_code
      FROM tms_organizations
     WHERE org_id = p_org_id
       AND status = 'ACTIVE';

    INSERT INTO tms_tickets(
      org_id,category_id,ticket_ref,subject,description,priority,status,
      requester_user_id,created_by
    )
    VALUES(
      p_org_id,p_category_id,'TEMP',p_subject,p_description,p_priority,'NEW',
      p_requester_user_id,COALESCE(SYS_CONTEXT('APEX$SESSION','APP_USER'),USER)
    )
    RETURNING ticket_id INTO p_ticket_id;

    UPDATE tms_tickets
       SET ticket_ref = l_org_code || '-' || TO_CHAR(SYSDATE,'YYYY') || '-' ||
                        LPAD(p_ticket_id,6,'0')
     WHERE ticket_id = p_ticket_id;

    INSERT INTO tms_ticket_history(
      ticket_id,org_id,old_status,new_status,actor_user_id,created_by
    )
    VALUES(
      p_ticket_id,p_org_id,NULL,'NEW',p_requester_user_id,
      COALESCE(SYS_CONTEXT('APEX$SESSION','APP_USER'),USER)
    );
  END;

  PROCEDURE change_status(
    p_ticket_id IN NUMBER,
    p_new_status IN VARCHAR2,
    p_comment IN VARCHAR2 DEFAULT NULL
  ) IS
    l_old_status tms_tickets.status%TYPE;
    l_org_id tms_tickets.org_id%TYPE;
  BEGIN
    SELECT status,org_id
      INTO l_old_status,l_org_id
      FROM tms_tickets
     WHERE ticket_id = p_ticket_id
       FOR UPDATE;

    IF l_old_status = 'CLOSED' AND p_new_status <> 'REOPENED' THEN
      RAISE_APPLICATION_ERROR(-20013,'Closed ticket can only be changed through the controlled reopen process.');
    END IF;

    UPDATE tms_tickets
       SET status = p_new_status,
           updated_date = SYSTIMESTAMP,
           updated_by = COALESCE(SYS_CONTEXT('APEX$SESSION','APP_USER'),USER),
           record_version = record_version + 1
     WHERE ticket_id = p_ticket_id;

    INSERT INTO tms_ticket_history(
      ticket_id,org_id,old_status,new_status,comment_text,created_by
    )
    VALUES(
      p_ticket_id,l_org_id,l_old_status,p_new_status,p_comment,
      COALESCE(SYS_CONTEXT('APEX$SESSION','APP_USER'),USER)
    );
  END;
END pkg_tms_ticket;
/
