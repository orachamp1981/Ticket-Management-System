/*
====================================================================
MULTI-ORGANIZATION TICKET MANAGEMENT SYSTEM
AUDIT ENGINE
Blueprint Version : v1.5

FILE : 06_audit_triggers.sql

PURPOSE
--------------------------------------------------------------------
Central, immutable audit engine for TMS business operations.

RULES
--------------------------------------------------------------------
1. All audit writes go through PKG_TMS_AUDIT.LOG_CHANGE.
2. Audit records are INSERT only.
3. UPDATE/DELETE of TMS_AUDIT_LOG is rejected at database level.
4. Actor is resolved from the current APEX session.
5. Session organization is captured with every audit record.
6. Old and new row images are stored as JSON.
7. Ticket-related business tables are audited automatically.
8. The audit engine does not perform authorization decisions.
9. Audit failure must not silently disappear.
====================================================================
*/


/* ================================================================
   1. CENTRAL AUDIT PACKAGE
   ================================================================ */

CREATE OR REPLACE PACKAGE PKG_TMS_AUDIT AS

    PROCEDURE LOG_CHANGE (
        P_TABLE_NAME      IN VARCHAR2,
        P_PK_VALUE        IN VARCHAR2,
        P_ACTION_TYPE     IN VARCHAR2,
        P_OLD_VALUE       IN CLOB DEFAULT NULL,
        P_NEW_VALUE       IN CLOB DEFAULT NULL,
        P_ACTOR            IN VARCHAR2 DEFAULT NULL,
        P_SESSION_ORG_ID  IN NUMBER DEFAULT NULL
    );

END PKG_TMS_AUDIT;
/

/* ================================================================
   2. CENTRAL AUDIT PACKAGE BODY
   ================================================================ */

CREATE OR REPLACE PACKAGE BODY PKG_TMS_AUDIT AS

    PROCEDURE LOG_CHANGE (
        P_TABLE_NAME      IN VARCHAR2,
        P_PK_VALUE        IN VARCHAR2,
        P_ACTION_TYPE     IN VARCHAR2,
        P_OLD_VALUE       IN CLOB DEFAULT NULL,
        P_NEW_VALUE       IN CLOB DEFAULT NULL,
        P_ACTOR            IN VARCHAR2 DEFAULT NULL,
        P_SESSION_ORG_ID  IN NUMBER DEFAULT NULL
    )
    IS
        L_ACTOR           VARCHAR2(255);
        L_SESSION_ORG_ID  NUMBER;
        L_ACTION_TYPE     VARCHAR2(10);
    BEGIN

        /* --------------------------------------------------------
           Validate action.
           -------------------------------------------------------- */

        L_ACTION_TYPE := UPPER(TRIM(P_ACTION_TYPE));

        IF L_ACTION_TYPE NOT IN ('INSERT', 'UPDATE', 'DELETE') THEN

            RAISE_APPLICATION_ERROR(
                -20101,
                'TMS-AUDIT-001: Invalid audit action.'
            );

        END IF;


        /* --------------------------------------------------------
           Table name is required.
           -------------------------------------------------------- */

        IF P_TABLE_NAME IS NULL THEN

            RAISE_APPLICATION_ERROR(
                -20102,
                'TMS-AUDIT-002: Audit table name is required.'
            );

        END IF;


        /* --------------------------------------------------------
           Primary-key value is required.
           -------------------------------------------------------- */

        IF P_PK_VALUE IS NULL THEN

            RAISE_APPLICATION_ERROR(
                -20103,
                'TMS-AUDIT-003: Audit primary-key value is required.'
            );

        END IF;


        /* --------------------------------------------------------
           Resolve actor.

           APEX session user is preferred.

           Outside APEX, database session user is retained so that
           administrative/database activity is still attributable.
           -------------------------------------------------------- */

        L_ACTOR :=
            NVL(
                P_ACTOR,
                SYS_CONTEXT(
                    'APEX$SESSION',
                    'APP_USER'
                )
            );

        L_ACTOR :=
            NVL(
                L_ACTOR,
                SYS_CONTEXT(
                    'USERENV',
                    'SESSION_USER'
                )
            );


        IF L_ACTOR IS NULL THEN
            L_ACTOR := 'UNKNOWN';
        END IF;


        /* --------------------------------------------------------
           Resolve organization context.

           Caller may explicitly provide it, otherwise obtain it
           from the current TMS session context.
           -------------------------------------------------------- */

        L_SESSION_ORG_ID := P_SESSION_ORG_ID;

        IF L_SESSION_ORG_ID IS NULL THEN

            BEGIN

                L_SESSION_ORG_ID :=
                    TO_NUMBER(
                        APEX_UTIL.GET_SESSION_STATE(
                            'G_ORG_ID'
                        )
                    );

            EXCEPTION
                WHEN OTHERS THEN
                    L_SESSION_ORG_ID := NULL;
            END;

        END IF;


        /* --------------------------------------------------------
           Write immutable audit record.
           -------------------------------------------------------- */

        INSERT INTO TMS_AUDIT_LOG (
            TABLE_NAME,
            PK_VALUE,
            ACTION_TYPE,
            OLD_VALUE,
            NEW_VALUE,
            ACTOR,
            ACTION_DATE,
            SESSION_ORG_ID
        )
        VALUES (
            UPPER(P_TABLE_NAME),
            P_PK_VALUE,
            L_ACTION_TYPE,
            P_OLD_VALUE,
            P_NEW_VALUE,
            L_ACTOR,
            SYSTIMESTAMP,
            L_SESSION_ORG_ID
        );


        /*
           Deliberately no COMMIT here.

           When called by a business-table trigger, the audit record
           belongs to the same transaction as the business change.

           If the business transaction rolls back, its audit record
           also rolls back.

           This preserves transactional consistency.
        */

    END LOG_CHANGE;

END PKG_TMS_AUDIT;
/

/* ================================================================
   3. AUDIT IMMUTABILITY
   ================================================================ */

CREATE OR REPLACE TRIGGER TRG_TMS_AUDIT_IMMUTABLE
BEFORE UPDATE OR DELETE ON TMS_AUDIT_LOG
FOR EACH ROW
BEGIN

    RAISE_APPLICATION_ERROR(
        -20110,
        'TMS-AUDIT-010: Audit records are immutable.'
    );

END;
/

/* ================================================================
   4. TICKET AUDIT
   ================================================================ */

CREATE OR REPLACE TRIGGER TRG_TMS_TICKETS_AUDIT
AFTER INSERT OR UPDATE OR DELETE ON TMS_TICKETS
FOR EACH ROW
DECLARE
    L_OLD_VALUE CLOB;
    L_NEW_VALUE CLOB;
BEGIN

    IF INSERTING THEN

        SELECT JSON_OBJECT(
                   'TICKET_ID' VALUE :NEW.TICKET_ID,
                   'ORG_ID' VALUE :NEW.ORG_ID,
                   'TICKET_REF' VALUE :NEW.TICKET_REF,
                   'SUBJECT' VALUE :NEW.SUBJECT,
                   'PRIORITY' VALUE :NEW.PRIORITY,
                   'STATUS' VALUE :NEW.STATUS,
                   'REQUESTER_USER_ID' VALUE :NEW.REQUESTER_USER_ID,
                   'ASSIGNED_USER_ID' VALUE :NEW.ASSIGNED_USER_ID,
                   'ASSIGNED_DEPARTMENT_ID' VALUE :NEW.ASSIGNED_DEPARTMENT_ID,
                   'OPENED_DATE' VALUE :NEW.OPENED_DATE,
                   'RESOLVED_DATE' VALUE :NEW.RESOLVED_DATE,
                   'CLOSED_DATE' VALUE :NEW.CLOSED_DATE
                   RETURNING CLOB
               )
        INTO L_NEW_VALUE
        FROM DUAL;

        PKG_TMS_AUDIT.LOG_CHANGE(
            P_TABLE_NAME     => 'TMS_TICKETS',
            P_PK_VALUE       => TO_CHAR(:NEW.TICKET_ID),
            P_ACTION_TYPE    => 'INSERT',
            P_OLD_VALUE      => NULL,
            P_NEW_VALUE      => L_NEW_VALUE,
            P_SESSION_ORG_ID => :NEW.ORG_ID
        );


    ELSIF UPDATING THEN

        SELECT JSON_OBJECT(
                   'TICKET_ID' VALUE :OLD.TICKET_ID,
                   'ORG_ID' VALUE :OLD.ORG_ID,
                   'TICKET_REF' VALUE :OLD.TICKET_REF,
                   'SUBJECT' VALUE :OLD.SUBJECT,
                   'PRIORITY' VALUE :OLD.PRIORITY,
                   'STATUS' VALUE :OLD.STATUS,
                   'REQUESTER_USER_ID' VALUE :OLD.REQUESTER_USER_ID,
                   'ASSIGNED_USER_ID' VALUE :OLD.ASSIGNED_USER_ID,
                   'ASSIGNED_DEPARTMENT_ID' VALUE :OLD.ASSIGNED_DEPARTMENT_ID,
                   'OPENED_DATE' VALUE :OLD.OPENED_DATE,
                   'RESOLVED_DATE' VALUE :OLD.RESOLVED_DATE,
                   'CLOSED_DATE' VALUE :OLD.CLOSED_DATE
                   RETURNING CLOB
               )
        INTO L_OLD_VALUE
        FROM DUAL;


        SELECT JSON_OBJECT(
                   'TICKET_ID' VALUE :NEW.TICKET_ID,
                   'ORG_ID' VALUE :NEW.ORG_ID,
                   'TICKET_REF' VALUE :NEW.TICKET_REF,
                   'SUBJECT' VALUE :NEW.SUBJECT,
                   'PRIORITY' VALUE :NEW.PRIORITY,
                   'STATUS' VALUE :NEW.STATUS,
                   'REQUESTER_USER_ID' VALUE :NEW.REQUESTER_USER_ID,
                   'ASSIGNED_USER_ID' VALUE :NEW.ASSIGNED_USER_ID,
                   'ASSIGNED_DEPARTMENT_ID' VALUE :NEW.ASSIGNED_DEPARTMENT_ID,
                   'OPENED_DATE' VALUE :NEW.OPENED_DATE,
                   'RESOLVED_DATE' VALUE :NEW.RESOLVED_DATE,
                   'CLOSED_DATE' VALUE :NEW.CLOSED_DATE
                   RETURNING CLOB
               )
        INTO L_NEW_VALUE
        FROM DUAL;


        PKG_TMS_AUDIT.LOG_CHANGE(
            P_TABLE_NAME      => 'TMS_TICKETS',
            P_PK_VALUE        => TO_CHAR(:NEW.TICKET_ID),
            P_ACTION_TYPE     => 'UPDATE',
            P_OLD_VALUE       => L_OLD_VALUE,
            P_NEW_VALUE       => L_NEW_VALUE,
            P_SESSION_ORG_ID  => :NEW.ORG_ID
        );


    ELSIF DELETING THEN

        SELECT JSON_OBJECT(
                   'TICKET_ID' VALUE :OLD.TICKET_ID,
                   'ORG_ID' VALUE :OLD.ORG_ID,
                   'TICKET_REF' VALUE :OLD.TICKET_REF,
                   'SUBJECT' VALUE :OLD.SUBJECT,
                   'PRIORITY' VALUE :OLD.PRIORITY,
                   'STATUS' VALUE :OLD.STATUS
                   RETURNING CLOB
               )
        INTO L_OLD_VALUE
        FROM DUAL;


        PKG_TMS_AUDIT.LOG_CHANGE(
            P_TABLE_NAME      => 'TMS_TICKETS',
            P_PK_VALUE        => TO_CHAR(:OLD.TICKET_ID),
            P_ACTION_TYPE     => 'DELETE',
            P_OLD_VALUE       => L_OLD_VALUE,
            P_NEW_VALUE       => NULL,
            P_SESSION_ORG_ID  => :OLD.ORG_ID
        );

    END IF;

END;
/

/* ================================================================
   5. TICKET DETAILS
   ================================================================ */

CREATE OR REPLACE TRIGGER TRG_TMS_TICKET_DETAILS_AUDIT
AFTER INSERT OR UPDATE OR DELETE ON TMS_TICKET_DETAILS
FOR EACH ROW
DECLARE
    L_OLD_VALUE CLOB;
    L_NEW_VALUE CLOB;
BEGIN

    IF INSERTING THEN

        SELECT JSON_OBJECT(
                   'TICKET_DETAIL_ID' VALUE :NEW.TICKET_DETAIL_ID,
                   'TICKET_ID' VALUE :NEW.TICKET_ID,
                   'ORG_ID' VALUE :NEW.ORG_ID,
                   'DETAIL_JSON' VALUE :NEW.DETAIL_JSON
                   RETURNING CLOB
               )
        INTO L_NEW_VALUE
        FROM DUAL;


        PKG_TMS_AUDIT.LOG_CHANGE(
            'TMS_TICKET_DETAILS',
            TO_CHAR(:NEW.TICKET_DETAIL_ID),
            'INSERT',
            NULL,
            L_NEW_VALUE,
            NULL,
            :NEW.ORG_ID
        );


    ELSIF UPDATING THEN

        SELECT JSON_OBJECT(
                   'TICKET_DETAIL_ID' VALUE :OLD.TICKET_DETAIL_ID,
                   'TICKET_ID' VALUE :OLD.TICKET_ID,
                   'ORG_ID' VALUE :OLD.ORG_ID,
                   'DETAIL_JSON' VALUE :OLD.DETAIL_JSON
                   RETURNING CLOB
               )
        INTO L_OLD_VALUE
        FROM DUAL;


        SELECT JSON_OBJECT(
                   'TICKET_DETAIL_ID' VALUE :NEW.TICKET_DETAIL_ID,
                   'TICKET_ID' VALUE :NEW.TICKET_ID,
                   'ORG_ID' VALUE :NEW.ORG_ID,
                   'DETAIL_JSON' VALUE :NEW.DETAIL_JSON
                   RETURNING CLOB
               )
        INTO L_NEW_VALUE
        FROM DUAL;


        PKG_TMS_AUDIT.LOG_CHANGE(
            'TMS_TICKET_DETAILS',
            TO_CHAR(:NEW.TICKET_DETAIL_ID),
            'UPDATE',
            L_OLD_VALUE,
            L_NEW_VALUE,
            NULL,
            :NEW.ORG_ID
        );


    ELSIF DELETING THEN

        SELECT JSON_OBJECT(
                   'TICKET_DETAIL_ID' VALUE :OLD.TICKET_DETAIL_ID,
                   'TICKET_ID' VALUE :OLD.TICKET_ID,
                   'ORG_ID' VALUE :OLD.ORG_ID,
                   'DETAIL_JSON' VALUE :OLD.DETAIL_JSON
                   RETURNING CLOB
               )
        INTO L_OLD_VALUE
        FROM DUAL;


        PKG_TMS_AUDIT.LOG_CHANGE(
            'TMS_TICKET_DETAILS',
            TO_CHAR(:OLD.TICKET_DETAIL_ID),
            'DELETE',
            L_OLD_VALUE,
            NULL,
            NULL,
            :OLD.ORG_ID
        );

    END IF;

END;
/

/* ================================================================
   6. TICKET COMMENTS
   ================================================================ */

CREATE OR REPLACE TRIGGER TRG_TMS_TICKET_COMMENTS_AUDIT
AFTER INSERT OR UPDATE OR DELETE ON TMS_TICKET_COMMENTS
FOR EACH ROW
DECLARE
    L_OLD_VALUE CLOB;
    L_NEW_VALUE CLOB;
BEGIN

    IF INSERTING THEN

        SELECT JSON_OBJECT(
                   'COMMENT_ID' VALUE :NEW.COMMENT_ID,
                   'TICKET_ID' VALUE :NEW.TICKET_ID,
                   'ORG_ID' VALUE :NEW.ORG_ID,
                   'COMMENT_TYPE' VALUE :NEW.COMMENT_TYPE,
                   'COMMENT_TEXT' VALUE :NEW.COMMENT_TEXT
                   RETURNING CLOB
               )
        INTO L_NEW_VALUE
        FROM DUAL;


        PKG_TMS_AUDIT.LOG_CHANGE(
            'TMS_TICKET_COMMENTS',
            TO_CHAR(:NEW.COMMENT_ID),
            'INSERT',
            NULL,
            L_NEW_VALUE,
            NULL,
            :NEW.ORG_ID
        );


    ELSIF UPDATING THEN

        SELECT JSON_OBJECT(
                   'COMMENT_ID' VALUE :OLD.COMMENT_ID,
                   'TICKET_ID' VALUE :OLD.TICKET_ID,
                   'ORG_ID' VALUE :OLD.ORG_ID,
                   'COMMENT_TYPE' VALUE :OLD.COMMENT_TYPE,
                   'COMMENT_TEXT' VALUE :OLD.COMMENT_TEXT
                   RETURNING CLOB
               )
        INTO L_OLD_VALUE
        FROM DUAL;


        SELECT JSON_OBJECT(
                   'COMMENT_ID' VALUE :NEW.COMMENT_ID,
                   'TICKET_ID' VALUE :NEW.TICKET_ID,
                   'ORG_ID' VALUE :NEW.ORG_ID,
                   'COMMENT_TYPE' VALUE :NEW.COMMENT_TYPE,
                   'COMMENT_TEXT' VALUE :NEW.COMMENT_TEXT
                   RETURNING CLOB
               )
        INTO L_NEW_VALUE
        FROM DUAL;


        PKG_TMS_AUDIT.LOG_CHANGE(
            'TMS_TICKET_COMMENTS',
            TO_CHAR(:NEW.COMMENT_ID),
            'UPDATE',
            L_OLD_VALUE,
            L_NEW_VALUE,
            NULL,
            :NEW.ORG_ID
        );


    ELSIF DELETING THEN

        SELECT JSON_OBJECT(
                   'COMMENT_ID' VALUE :OLD.COMMENT_ID,
                   'TICKET_ID' VALUE :OLD.TICKET_ID,
                   'ORG_ID' VALUE :OLD.ORG_ID,
                   'COMMENT_TYPE' VALUE :OLD.COMMENT_TYPE,
                   'COMMENT_TEXT' VALUE :OLD.COMMENT_TEXT
                   RETURNING CLOB
               )
        INTO L_OLD_VALUE
        FROM DUAL;


        PKG_TMS_AUDIT.LOG_CHANGE(
            'TMS_TICKET_COMMENTS',
            TO_CHAR(:OLD.COMMENT_ID),
            'DELETE',
            L_OLD_VALUE,
            NULL,
            NULL,
            :OLD.ORG_ID
        );

    END IF;

END;
/

/* ================================================================
   7. TICKET ATTACHMENTS
   ================================================================ */

CREATE OR REPLACE TRIGGER TRG_TMS_TICKET_ATTACHMENTS_AUDIT
AFTER INSERT OR UPDATE OR DELETE ON TMS_TICKET_ATTACHMENTS
FOR EACH ROW
DECLARE
    L_OLD_VALUE CLOB;
    L_NEW_VALUE CLOB;
BEGIN

    IF INSERTING THEN

        SELECT JSON_OBJECT(
                   'ATTACHMENT_ID' VALUE :NEW.ATTACHMENT_ID,
                   'TICKET_ID' VALUE :NEW.TICKET_ID,
                   'ORG_ID' VALUE :NEW.ORG_ID,
                   'FILE_NAME' VALUE :NEW.FILE_NAME,
                   'MIME_TYPE' VALUE :NEW.MIME_TYPE,
                   'FILE_SIZE' VALUE :NEW.FILE_SIZE,
                   'STORAGE_REFERENCE' VALUE :NEW.STORAGE_REFERENCE
                   RETURNING CLOB
               )
        INTO L_NEW_VALUE
        FROM DUAL;


        PKG_TMS_AUDIT.LOG_CHANGE(
            'TMS_TICKET_ATTACHMENTS',
            TO_CHAR(:NEW.ATTACHMENT_ID),
            'INSERT',
            NULL,
            L_NEW_VALUE,
            NULL,
            :NEW.ORG_ID
        );


    ELSIF UPDATING THEN

        SELECT JSON_OBJECT(
                   'ATTACHMENT_ID' VALUE :OLD.ATTACHMENT_ID,
                   'TICKET_ID' VALUE :OLD.TICKET_ID,
                   'ORG_ID' VALUE :OLD.ORG_ID,
                   'FILE_NAME' VALUE :OLD.FILE_NAME,
                   'MIME_TYPE' VALUE :OLD.MIME_TYPE,
                   'FILE_SIZE' VALUE :OLD.FILE_SIZE,
                   'STORAGE_REFERENCE' VALUE :OLD.STORAGE_REFERENCE
                   RETURNING CLOB
               )
        INTO L_OLD_VALUE
        FROM DUAL;


        SELECT JSON_OBJECT(
                   'ATTACHMENT_ID' VALUE :NEW.ATTACHMENT_ID,
                   'TICKET_ID' VALUE :NEW.TICKET_ID,
                   'ORG_ID' VALUE :NEW.ORG_ID,
                   'FILE_NAME' VALUE :NEW.FILE_NAME,
                   'MIME_TYPE' VALUE :NEW.MIME_TYPE,
                   'FILE_SIZE' VALUE :NEW.FILE_SIZE,
                   'STORAGE_REFERENCE' VALUE :NEW.STORAGE_REFERENCE
                   RETURNING CLOB
               )
        INTO L_NEW_VALUE
        FROM DUAL;


        PKG_TMS_AUDIT.LOG_CHANGE(
            'TMS_TICKET_ATTACHMENTS',
            TO_CHAR(:NEW.ATTACHMENT_ID),
            'UPDATE',
            L_OLD_VALUE,
            L_NEW_VALUE,
            NULL,
            :NEW.ORG_ID
        );


    ELSIF DELETING THEN

        SELECT JSON_OBJECT(
                   'ATTACHMENT_ID' VALUE :OLD.ATTACHMENT_ID,
                   'TICKET_ID' VALUE :OLD.TICKET_ID,
                   'ORG_ID' VALUE :OLD.ORG_ID,
                   'FILE_NAME' VALUE :OLD.FILE_NAME,
                   'MIME_TYPE' VALUE :OLD.MIME_TYPE,
                   'FILE_SIZE' VALUE :OLD.FILE_SIZE,
                   'STORAGE_REFERENCE' VALUE :OLD.STORAGE_REFERENCE
                   RETURNING CLOB
               )
        INTO L_OLD_VALUE
        FROM DUAL;


        PKG_TMS_AUDIT.LOG_CHANGE(
            'TMS_TICKET_ATTACHMENTS',
            TO_CHAR(:OLD.ATTACHMENT_ID),
            'DELETE',
            L_OLD_VALUE,
            NULL,
            NULL,
            :OLD.ORG_ID
        );

    END IF;

END;
/

/* ================================================================
   8. TICKET HISTORY
   ================================================================ */

CREATE OR REPLACE TRIGGER TRG_TMS_TICKET_HISTORY_AUDIT
AFTER INSERT OR UPDATE OR DELETE ON TMS_TICKET_HISTORY
FOR EACH ROW
DECLARE
    L_OLD_VALUE CLOB;
    L_NEW_VALUE CLOB;
BEGIN

    IF INSERTING THEN

        SELECT JSON_OBJECT(
                   'HISTORY_ID' VALUE :NEW.HISTORY_ID,
                   'TICKET_ID' VALUE :NEW.TICKET_ID,
                   'ORG_ID' VALUE :NEW.ORG_ID,
                   'OLD_STATUS' VALUE :NEW.OLD_STATUS,
                   'NEW_STATUS' VALUE :NEW.NEW_STATUS,
                   'ACTOR_USER_ID' VALUE :NEW.ACTOR_USER_ID,
                   'COMMENT_TEXT' VALUE :NEW.COMMENT_TEXT
                   RETURNING CLOB
               )
        INTO L_NEW_VALUE
        FROM DUAL;


        PKG_TMS_AUDIT.LOG_CHANGE(
            'TMS_TICKET_HISTORY',
            TO_CHAR(:NEW.HISTORY_ID),
            'INSERT',
            NULL,
            L_NEW_VALUE,
            NULL,
            :NEW.ORG_ID
        );


    ELSIF UPDATING THEN

        SELECT JSON_OBJECT(
                   'HISTORY_ID' VALUE :OLD.HISTORY_ID,
                   'TICKET_ID' VALUE :OLD.TICKET_ID,
                   'ORG_ID' VALUE :OLD.ORG_ID,
                   'OLD_STATUS' VALUE :OLD.OLD_STATUS,
                   'NEW_STATUS' VALUE :OLD.NEW_STATUS,
                   'ACTOR_USER_ID' VALUE :OLD.ACTOR_USER_ID,
                   'COMMENT_TEXT' VALUE :OLD.COMMENT_TEXT
                   RETURNING CLOB
               )
        INTO L_OLD_VALUE
        FROM DUAL;


        SELECT JSON_OBJECT(
                   'HISTORY_ID' VALUE :NEW.HISTORY_ID,
                   'TICKET_ID' VALUE :NEW.TICKET_ID,
                   'ORG_ID' VALUE :NEW.ORG_ID,
                   'OLD_STATUS' VALUE :NEW.OLD_STATUS,
                   'NEW_STATUS' VALUE :NEW.NEW_STATUS,
                   'ACTOR_USER_ID' VALUE :NEW.ACTOR_USER_ID,
                   'COMMENT_TEXT' VALUE :NEW.COMMENT_TEXT
                   RETURNING CLOB
               )
        INTO L_NEW_VALUE
        FROM DUAL;


        PKG_TMS_AUDIT.LOG_CHANGE(
            'TMS_TICKET_HISTORY',
            TO_CHAR(:NEW.HISTORY_ID),
            'UPDATE',
            L_OLD_VALUE,
            L_NEW_VALUE,
            NULL,
            :NEW.ORG_ID
        );


    ELSIF DELETING THEN

        SELECT JSON_OBJECT(
                   'HISTORY_ID' VALUE :OLD.HISTORY_ID,
                   'TICKET_ID' VALUE :OLD.TICKET_ID,
                   'ORG_ID' VALUE :OLD.ORG_ID,
                   'OLD_STATUS' VALUE :OLD.OLD_STATUS,
                   'NEW_STATUS' VALUE :OLD.NEW_STATUS,
                   'ACTOR_USER_ID' VALUE :OLD.ACTOR_USER_ID,
                   'COMMENT_TEXT' VALUE :OLD.COMMENT_TEXT
                   RETURNING CLOB
               )
        INTO L_OLD_VALUE
        FROM DUAL;


        PKG_TMS_AUDIT.LOG_CHANGE(
            'TMS_TICKET_HISTORY',
            TO_CHAR(:OLD.HISTORY_ID),
            'DELETE',
            L_OLD_VALUE,
            NULL,
            NULL,
            :OLD.ORG_ID
        );

    END IF;

END;
/

/* ================================================================
   9. TICKET WATCHERS
   ================================================================ */

CREATE OR REPLACE TRIGGER TRG_TMS_TICKET_WATCHERS_AUDIT
AFTER INSERT OR UPDATE OR DELETE ON TMS_TICKET_WATCHERS
FOR EACH ROW
DECLARE
    L_OLD_VALUE CLOB;
    L_NEW_VALUE CLOB;
BEGIN

    IF INSERTING THEN

        SELECT JSON_OBJECT(
                   'TICKET_WATCHER_ID' VALUE :NEW.TICKET_WATCHER_ID,
                   'TICKET_ID' VALUE :NEW.TICKET_ID,
                   'ORG_ID' VALUE :NEW.ORG_ID,
                   'USER_ID' VALUE :NEW.USER_ID
                   RETURNING CLOB
               )
        INTO L_NEW_VALUE
        FROM DUAL;


        PKG_TMS_AUDIT.LOG_CHANGE(
            'TMS_TICKET_WATCHERS',
            TO_CHAR(:NEW.TICKET_WATCHER_ID),
            'INSERT',
            NULL,
            L_NEW_VALUE,
            NULL,
            :NEW.ORG_ID
        );


    ELSIF UPDATING THEN

        SELECT JSON_OBJECT(
                   'TICKET_WATCHER_ID' VALUE :OLD.TICKET_WATCHER_ID,
                   'TICKET_ID' VALUE :OLD.TICKET_ID,
                   'ORG_ID' VALUE :OLD.ORG_ID,
                   'USER_ID' VALUE :OLD.USER_ID
                   RETURNING CLOB
               )
        INTO L_OLD_VALUE
        FROM DUAL;


        SELECT JSON_OBJECT(
                   'TICKET_WATCHER_ID' VALUE :NEW.TICKET_WATCHER_ID,
                   'TICKET_ID' VALUE :NEW.TICKET_ID,
                   'ORG_ID' VALUE :NEW.ORG_ID,
                   'USER_ID' VALUE :NEW.USER_ID
                   RETURNING CLOB
               )
        INTO L_NEW_VALUE
        FROM DUAL;


        PKG_TMS_AUDIT.LOG_CHANGE(
            'TMS_TICKET_WATCHERS',
            TO_CHAR(:NEW.TICKET_WATCHER_ID),
            'UPDATE',
            L_OLD_VALUE,
            L_NEW_VALUE,
            NULL,
            :NEW.ORG_ID
        );


    ELSIF DELETING THEN

        SELECT JSON_OBJECT(
                   'TICKET_WATCHER_ID' VALUE :OLD.TICKET_WATCHER_ID,
                   'TICKET_ID' VALUE :OLD.TICKET_ID,
                   'ORG_ID' VALUE :OLD.ORG_ID,
                   'USER_ID' VALUE :OLD.USER_ID
                   RETURNING CLOB
               )
        INTO L_OLD_VALUE
        FROM DUAL;


        PKG_TMS_AUDIT.LOG_CHANGE(
            'TMS_TICKET_WATCHERS',
            TO_CHAR(:OLD.TICKET_WATCHER_ID),
            'DELETE',
            L_OLD_VALUE,
            NULL,
            NULL,
            :OLD.ORG_ID
        );

    END IF;

END;
/