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
           Table name is stored in normalized form.
           -------------------------------------------------------- */

        IF P_TABLE_NAME IS NULL THEN

            RAISE_APPLICATION_ERROR(
                -20102,
                'TMS-AUDIT-002: Audit table name is required.'
            );

        END IF;


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