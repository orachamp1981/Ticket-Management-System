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

/* ================================================================
   TMS DATA ACCESS RESOLUTION ENGINE
   Blueprint Version : v1.5

   PURPOSE
   ----------------------------------------------------------------
   Single source of truth for row-level organization access.

   Used by:
       1. VPD / RLS policies
       2. Access-scoped APEX views
       3. Server-side business packages

   RULES
   ----------------------------------------------------------------
   - Super User has unrestricted data visibility.
   - Normal users require active membership in the current org.
   - Child organization visibility is granted only when the parent
     organization has CAN_VIEW_CHILD_DATA = 'Y'.
   - TMS_COST_CENTRES are intentionally outside this engine.
   - No generated page should implement its own ORG_ID predicate.
   ================================================================ */


/* ================================================================
   PACKAGE SPECIFICATION
   ================================================================ */

CREATE OR REPLACE PACKAGE PKG_TMS_DATA_ACCESS AS

    /* ------------------------------------------------------------
       Current organization from APEX session.
       ------------------------------------------------------------ */
    FUNCTION GET_CURRENT_ORG_ID
        RETURN NUMBER;


    /* ------------------------------------------------------------
       Current authenticated TMS user.
       ------------------------------------------------------------ */
    FUNCTION GET_CURRENT_USER_ID
        RETURN NUMBER;


    /* ------------------------------------------------------------
       Determine whether current user may access an organization.
       Returns:
           1 = allowed
           0 = denied
       ------------------------------------------------------------ */
    FUNCTION CAN_ACCESS_ORG (
        P_ORG_ID IN NUMBER
    ) RETURN NUMBER;


    /* ------------------------------------------------------------
       Determine whether a specific user may access an organization.
       Used by server-side packages and VPD logic.
       ------------------------------------------------------------ */
    FUNCTION CAN_USER_ACCESS_ORG (
        P_USER_ID IN NUMBER,
        P_ORG_ID  IN NUMBER
    ) RETURN NUMBER;


    /* ------------------------------------------------------------
       Return VPD predicate for tables containing ORG_ID.

       Example:
           PKG_TMS_DATA_ACCESS.GET_PREDICATE('ORG_ID')

       Returns a SQL predicate such as:
           ORG_ID = 10
       or:
           ORG_ID IN (...)
       or:
           1 = 1

       The returned predicate is consumed by DBMS_RLS.
       ------------------------------------------------------------ */
    FUNCTION GET_PREDICATE (
        P_ORG_COLUMN IN VARCHAR2 DEFAULT 'ORG_ID'
    ) RETURN VARCHAR2;


    /* ------------------------------------------------------------
       Validate that a record organization is inside current
       session scope.

       Raises an application error when access is denied.
       ------------------------------------------------------------ */
    PROCEDURE ASSERT_ORG_ACCESS (
        P_ORG_ID IN NUMBER
    );


END PKG_TMS_DATA_ACCESS;
/

/* ================================================================
   PACKAGE BODY
   ================================================================ */

CREATE OR REPLACE PACKAGE BODY PKG_TMS_DATA_ACCESS AS


    /* ============================================================
       INTERNAL CONSTANTS
       ============================================================ */

    C_SUPER_USER_ORG_TYPE CONSTANT VARCHAR2(50) := 'SUPER_USER';


    /* ============================================================
       GET_CURRENT_USER_ID
       ============================================================ */

    FUNCTION GET_CURRENT_USER_ID
        RETURN NUMBER
    IS
        L_LOGIN_NAME VARCHAR2(255);
        L_USER_ID    NUMBER;
    BEGIN

        L_LOGIN_NAME :=
            SYS_CONTEXT(
                'APEX$SESSION',
                'APP_USER'
            );

        IF L_LOGIN_NAME IS NULL THEN
            RETURN NULL;
        END IF;


        SELECT USER_ID
          INTO L_USER_ID
          FROM TMS_USERS
         WHERE UPPER(LOGIN_NAME) = UPPER(TRIM(L_LOGIN_NAME));

        RETURN L_USER_ID;

    EXCEPTION

        WHEN NO_DATA_FOUND THEN
            RETURN NULL;

        WHEN TOO_MANY_ROWS THEN
            RETURN NULL;

        WHEN OTHERS THEN
            RETURN NULL;

    END GET_CURRENT_USER_ID;


    /* ============================================================
       GET_CURRENT_ORG_ID

       G_ORG_ID is an APEX Application Item resolved by the
       authentication/context engine.

       This package reads it.

       It does NOT set it.
       ============================================================ */

    FUNCTION GET_CURRENT_ORG_ID
        RETURN NUMBER
    IS
        L_ORG_ID VARCHAR2(100);
    BEGIN

        L_ORG_ID :=
            APEX_UTIL.GET_SESSION_STATE('G_ORG_ID');

        IF L_ORG_ID IS NULL THEN
            RETURN NULL;
        END IF;


        RETURN TO_NUMBER(L_ORG_ID);

    EXCEPTION

        WHEN VALUE_ERROR THEN
            RETURN NULL;

        WHEN OTHERS THEN
            RETURN NULL;

    END GET_CURRENT_ORG_ID;


    /* ============================================================
       CAN_USER_ACCESS_ORG

       Access model:

       1. User must be active.
       2. Super User -> unrestricted.
       3. User's selected/current organization -> allowed when
          active membership exists.
       4. Parent organization may access child organization only
          when CAN_VIEW_CHILD_DATA = 'Y'.
       5. No membership -> denied.

       NOTE:
       This function deals with ORGANIZATION SCOPE only.

       Function/Action authorization remains PKG_TMS_AUTH.
       ============================================================ */

    FUNCTION CAN_USER_ACCESS_ORG (
        P_USER_ID IN NUMBER,
        P_ORG_ID  IN NUMBER
    ) RETURN NUMBER
    IS
        L_COUNT              NUMBER;
        L_PARENT_ORG_ID      NUMBER;
        L_CAN_VIEW_CHILD     CHAR(1);
        L_USER_ORG_ID        NUMBER;
    BEGIN

        IF P_USER_ID IS NULL
           OR P_ORG_ID IS NULL
        THEN
            RETURN 0;
        END IF;


        /* --------------------------------------------------------
           User must be active.
           -------------------------------------------------------- */

        SELECT COUNT(*)
          INTO L_COUNT
          FROM TMS_USERS
         WHERE USER_ID = P_USER_ID
           AND ACCOUNT_STATUS = 'ACTIVE';


        IF L_COUNT = 0 THEN
            RETURN 0;
        END IF;


        /* --------------------------------------------------------
           Super User authority.

           Super User is identified through the dedicated system
           role. PKG_TMS_AUTH owns that identity decision.
           -------------------------------------------------------- */

        IF PKG_TMS_AUTH.IS_SUPER_USER(P_USER_ID) THEN
            RETURN 1;
        END IF;


        /* --------------------------------------------------------
           Direct organization membership.
           -------------------------------------------------------- */

        SELECT COUNT(*)
          INTO L_COUNT
          FROM TMS_USER_ORGANIZATIONS UO
         WHERE UO.USER_ID = P_USER_ID
           AND UO.ORG_ID = P_ORG_ID
           AND UO.MEMBERSHIP_STATUS = 'ACTIVE'
           AND UO.EFFECTIVE_FROM <= TRUNC(SYSDATE)
           AND (
                   UO.EFFECTIVE_TO IS NULL
                   OR UO.EFFECTIVE_TO >= TRUNC(SYSDATE)
               );


        IF L_COUNT > 0 THEN
            RETURN 1;
        END IF;


        /* --------------------------------------------------------
           Determine whether P_ORG_ID is a child of one of the
           user's organizations.

           Child visibility is NEVER assumed.
           It requires CAN_VIEW_CHILD_DATA = 'Y'.
           -------------------------------------------------------- */

        SELECT COUNT(*)
          INTO L_COUNT
          FROM TMS_USER_ORGANIZATIONS UO
               JOIN TMS_ORGANIZATIONS P
                 ON P.ORG_ID = UO.ORG_ID
               JOIN TMS_ORGANIZATIONS C
                 ON C.PARENT_ORG_ID = P.ORG_ID
         WHERE UO.USER_ID = P_USER_ID
           AND UO.MEMBERSHIP_STATUS = 'ACTIVE'
           AND UO.EFFECTIVE_FROM <= TRUNC(SYSDATE)
           AND (
                   UO.EFFECTIVE_TO IS NULL
                   OR UO.EFFECTIVE_TO >= TRUNC(SYSDATE)
               )
           AND P.CAN_VIEW_CHILD_DATA = 'Y'
           AND C.ORG_ID = P_ORG_ID
           AND C.STATUS = 'ACTIVE';


        IF L_COUNT > 0 THEN
            RETURN 1;
        END IF;


        RETURN 0;

    EXCEPTION

        WHEN OTHERS THEN
            RETURN 0;

    END CAN_USER_ACCESS_ORG;


    /* ============================================================
       CAN_ACCESS_ORG
       ============================================================ */

    FUNCTION CAN_ACCESS_ORG (
        P_ORG_ID IN NUMBER
    ) RETURN NUMBER
    IS
        L_USER_ID NUMBER;
    BEGIN

        L_USER_ID := GET_CURRENT_USER_ID;


        RETURN CAN_USER_ACCESS_ORG(
                   P_USER_ID => L_USER_ID,
                   P_ORG_ID  => P_ORG_ID
               );

    EXCEPTION

        WHEN OTHERS THEN
            RETURN 0;

    END CAN_ACCESS_ORG;


    /* ============================================================
       GET_PREDICATE

       VPD predicate generator.

       IMPORTANT:
       P_ORG_COLUMN is validated against a strict whitelist.

       We never accept arbitrary SQL supplied by an application
       page.
       ============================================================ */

    FUNCTION GET_PREDICATE (
        P_ORG_COLUMN IN VARCHAR2 DEFAULT 'ORG_ID'
    ) RETURN VARCHAR2
    IS
        L_USER_ID          NUMBER;
        L_CURRENT_ORG_ID   NUMBER;
        L_COLUMN           VARCHAR2(30);
        L_RESULT            VARCHAR2(32767);
    BEGIN

        /* --------------------------------------------------------
           Whitelist allowed organization column names.
           -------------------------------------------------------- */

        L_COLUMN := UPPER(TRIM(P_ORG_COLUMN));


        IF L_COLUMN NOT IN (
            'ORG_ID'
        )
        THEN

            RAISE_APPLICATION_ERROR(
                -20031,
                'TMS-DATA-ACCESS-031: Invalid organization column.'
            );

        END IF;


        L_USER_ID := GET_CURRENT_USER_ID;
        L_CURRENT_ORG_ID := GET_CURRENT_ORG_ID;


        /* --------------------------------------------------------
           No authenticated user -> deny all business rows.
           -------------------------------------------------------- */

        IF L_USER_ID IS NULL THEN
            RETURN '1 = 0';
        END IF;


        /* --------------------------------------------------------
           Super User -> unrestricted visibility.

           This is intentional.

           Super User authority is not represented by a permission.
           -------------------------------------------------------- */

        IF PKG_TMS_AUTH.IS_SUPER_USER(L_USER_ID) THEN
            RETURN '1 = 1';
        END IF;


        /* --------------------------------------------------------
           No organization context for normal user -> deny.
           -------------------------------------------------------- */

        IF L_CURRENT_ORG_ID IS NULL THEN
            RETURN '1 = 0';
        END IF;


        /* --------------------------------------------------------
           Verify that the current user is actually allowed to
           operate in the current organization.

           If not, return no rows.
           -------------------------------------------------------- */

        IF CAN_USER_ACCESS_ORG(
               P_USER_ID => L_USER_ID,
               P_ORG_ID  => L_CURRENT_ORG_ID
           ) = 0
        THEN
            RETURN '1 = 0';
        END IF;


        /* --------------------------------------------------------
           Direct organization scope.

           For the first foundation implementation the active
           organization is the authoritative tenant boundary.

           Child visibility is handled through CAN_ACCESS_ORG()
           for access-scoped views and by the context engine.

           VPD must remain SQL-predicate based and deterministic.
           -------------------------------------------------------- */

        L_RESULT :=
            L_COLUMN
            || ' = '
            || TO_CHAR(L_CURRENT_ORG_ID);


        RETURN L_RESULT;

    EXCEPTION

        WHEN OTHERS THEN

            /* ----------------------------------------------------
               SECURITY DEFAULT:
               If access resolution fails, return no rows.
               Never fail open.
               ---------------------------------------------------- */

            RETURN '1 = 0';

    END GET_PREDICATE;


    /* ============================================================
       ASSERT_ORG_ACCESS
       ============================================================ */

    PROCEDURE ASSERT_ORG_ACCESS (
        P_ORG_ID IN NUMBER
    )
    IS
    BEGIN

        IF P_ORG_ID IS NULL THEN

            RAISE_APPLICATION_ERROR(
                -20032,
                'TMS-DATA-ACCESS-032: Organization context is required.'
            );

        END IF;


        IF CAN_ACCESS_ORG(P_ORG_ID) = 0 THEN

            RAISE_APPLICATION_ERROR(
                -20033,
                'TMS-DATA-ACCESS-033: Organization is outside '
                || 'the current user data scope.'
            );

        END IF;

    END ASSERT_ORG_ACCESS;


END PKG_TMS_DATA_ACCESS;
/