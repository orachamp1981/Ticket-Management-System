/* ================================================================
   TMS REFERENCE / FOUNDATION SEED DATA
   Blueprint Version : v1.5
   Purpose            : Foundation reference data and Super User
                        organization setup.

   IMPORTANT:
   - Super User is NOT represented by a "SUPER_ADMIN_ALL" permission.
   - SUPER_USER role identifies the platform authority.
   - PKG_TMS_AUTH bypasses normal permission restriction for Super User.
   - Business rules, workflow, audit and data integrity still apply.
   - Super User Organization is NOT a customer organization.
   ================================================================ */


/* ================================================================
   1. SUPER USER ORGANIZATION
   ================================================================ */

MERGE INTO TMS_ORGANIZATIONS T
USING (
    SELECT
        'TMS_SUPER_USER' AS ORG_CODE,
        'TMS Super User Organization' AS ORG_NAME
    FROM DUAL
) S
ON (T.ORG_CODE = S.ORG_CODE)

WHEN MATCHED THEN
    UPDATE SET
        T.ORG_NAME              = S.ORG_NAME,
        T.STATUS                = 'ACTIVE',
        T.ORG_TYPE              = 'SUPER_USER',
        T.CAN_VIEW_CHILD_DATA   = 'Y',
        T.UPDATED_BY            = 'SYSTEM',
        T.UPDATED_DATE          = SYSTIMESTAMP

WHEN NOT MATCHED THEN
    INSERT (
        ORG_CODE,
        ORG_NAME,
        PARENT_ORG_ID,
        STATUS,
        ORG_TYPE,
        CAN_VIEW_CHILD_DATA,
        CREATED_BY,
        CREATED_DATE,
        RECORD_VERSION
    )
    VALUES (
        S.ORG_CODE,
        S.ORG_NAME,
        NULL,
        'ACTIVE',
        'SUPER_USER',
        'Y',
        'SYSTEM',
        SYSTIMESTAMP,
        1
    );


/* ================================================================
   2. SUPER USER SYSTEM ROLE
   ================================================================ */

MERGE INTO TMS_ROLES T
USING (
    SELECT
        'SUPER_USER' AS ROLE_CODE,
        'Super User' AS ROLE_NAME
    FROM DUAL
) S
ON (
       T.ORG_ID IS NULL
   AND T.ROLE_CODE = S.ROLE_CODE
)

WHEN MATCHED THEN
    UPDATE SET
        T.ROLE_NAME   = S.ROLE_NAME,
        T.STATUS      = 'ACTIVE',
        T.UPDATED_BY  = 'SYSTEM',
        T.UPDATED_DATE = SYSTIMESTAMP

WHEN NOT MATCHED THEN
    INSERT (
        ORG_ID,
        ROLE_CODE,
        ROLE_NAME,
        STATUS,
        CREATED_BY,
        CREATED_DATE,
        RECORD_VERSION
    )
    VALUES (
        NULL,
        S.ROLE_CODE,
        S.ROLE_NAME,
        'ACTIVE',
        'SYSTEM',
        SYSTIMESTAMP,
        1
    );


/* ================================================================
   3. SUPER USER ROLE DETAILS
   ================================================================ */

MERGE INTO TMS_ROLE_DETAILS T
USING (
    SELECT
        R.ROLE_ID
    FROM TMS_ROLES R
    WHERE R.ORG_ID IS NULL
      AND R.ROLE_CODE = 'SUPER_USER'
) S
ON (T.ROLE_ID = S.ROLE_ID)

WHEN MATCHED THEN
    UPDATE SET
        T.ROLE_DESCRIPTION = 'Platform Super User authority. '
                           || 'Not restricted by Function/Action permissions. '
                           || 'Business rules, workflow, audit and data '
                           || 'integrity remain mandatory.',
        T.ROLE_CATEGORY    = 'PLATFORM',
        T.IS_SYSTEM_ROLE   = 'Y',
        T.UPDATED_BY       = 'SYSTEM',
        T.UPDATED_DATE     = SYSTIMESTAMP

WHEN NOT MATCHED THEN
    INSERT (
        ROLE_ID,
        ROLE_DESCRIPTION,
        ROLE_CATEGORY,
        IS_SYSTEM_ROLE,
        CREATED_BY,
        CREATED_DATE,
        RECORD_VERSION
    )
    VALUES (
        S.ROLE_ID,
        'Platform Super User authority. '
        || 'Not restricted by Function/Action permissions. '
        || 'Business rules, workflow, audit and data integrity '
        || 'remain mandatory.',
        'PLATFORM',
        'Y',
        'SYSTEM',
        SYSTIMESTAMP,
        1
    );


/* ================================================================
   4. CORE TICKET FUNCTION
   ================================================================ */

MERGE INTO TMS_FUNCTIONS T
USING (
    SELECT
        'TICKET' AS FUNCTION_CODE,
        'Ticket Management' AS FUNCTION_NAME
    FROM DUAL
) S
ON (T.FUNCTION_CODE = S.FUNCTION_CODE)

WHEN MATCHED THEN
    UPDATE SET
        T.FUNCTION_NAME = S.FUNCTION_NAME,
        T.UPDATED_BY    = 'SYSTEM',
        T.UPDATED_DATE  = SYSTIMESTAMP

WHEN NOT MATCHED THEN
    INSERT (
        FUNCTION_CODE,
        FUNCTION_NAME,
        CREATED_BY,
        CREATED_DATE,
        RECORD_VERSION
    )
    VALUES (
        S.FUNCTION_CODE,
        S.FUNCTION_NAME,
        'SYSTEM',
        SYSTIMESTAMP,
        1
    );


/* ================================================================
   5. CORE ACTIONS
   ================================================================ */

MERGE INTO TMS_ACTIONS T
USING (
    SELECT 'CREATE'   ACTION_CODE, 'Create'   ACTION_NAME FROM DUAL
    UNION ALL
    SELECT 'VIEW',    'View'                    FROM DUAL
    UNION ALL
    SELECT 'UPDATE',  'Update'                  FROM DUAL
    UNION ALL
    SELECT 'CLOSE',   'Close'                   FROM DUAL
    UNION ALL
    SELECT 'REASSIGN','Reassign'                FROM DUAL
    UNION ALL
    SELECT 'REOPEN',  'Reopen'                  FROM DUAL
) S
ON (T.ACTION_CODE = S.ACTION_CODE)

WHEN MATCHED THEN
    UPDATE SET
        T.ACTION_NAME = S.ACTION_NAME,
        T.UPDATED_BY  = 'SYSTEM',
        T.UPDATED_DATE = SYSTIMESTAMP

WHEN NOT MATCHED THEN
    INSERT (
        ACTION_CODE,
        ACTION_NAME,
        CREATED_BY,
        CREATED_DATE,
        RECORD_VERSION
    )
    VALUES (
        S.ACTION_CODE,
        S.ACTION_NAME,
        'SYSTEM',
        SYSTIMESTAMP,
        1
    );


/* ================================================================
   6. TICKET PERMISSIONS
   ================================================================ */

MERGE INTO TMS_PERMISSIONS T
USING (
    SELECT
        F.FUNCTION_ID,
        A.ACTION_ID,
        F.FUNCTION_CODE || '.' || A.ACTION_CODE AS PERMISSION_CODE
    FROM TMS_FUNCTIONS F
    CROSS JOIN TMS_ACTIONS A
    WHERE F.FUNCTION_CODE = 'TICKET'
) S
ON (T.PERMISSION_CODE = S.PERMISSION_CODE)

WHEN MATCHED THEN
    UPDATE SET
        T.FUNCTION_ID = S.FUNCTION_ID,
        T.ACTION_ID   = S.ACTION_ID,
        T.UPDATED_BY  = 'SYSTEM',
        T.UPDATED_DATE = SYSTIMESTAMP

WHEN NOT MATCHED THEN
    INSERT (
        FUNCTION_ID,
        ACTION_ID,
        PERMISSION_CODE,
        CREATED_BY,
        CREATED_DATE,
        RECORD_VERSION
    )
    VALUES (
        S.FUNCTION_ID,
        S.ACTION_ID,
        S.PERMISSION_CODE,
        'SYSTEM',
        SYSTIMESTAMP,
        1
    );


/* ================================================================
   7. GRANT CORE TICKET PERMISSIONS TO SUPER USER ROLE
   ----------------------------------------------------------------
   This is NOT what makes the Super User unrestricted.

   PKG_TMS_AUTH.IS_SUPER_USER() is the authority bypass.

   These permission links are retained as a clean foundation and
   allow the Super User role to remain structurally complete.
   ================================================================ */

INSERT INTO TMS_ROLE_PERMISSIONS (
    ROLE_ID,
    PERMISSION_ID,
    CREATED_BY,
    CREATED_DATE
)
SELECT
    R.ROLE_ID,
    P.PERMISSION_ID,
    'SYSTEM',
    SYSTIMESTAMP
FROM TMS_ROLES R
CROSS JOIN TMS_PERMISSIONS P
WHERE R.ORG_ID IS NULL
  AND R.ROLE_CODE = 'SUPER_USER'
  AND P.PERMISSION_CODE IN (
        'TICKET.CREATE',
        'TICKET.VIEW',
        'TICKET.UPDATE',
        'TICKET.CLOSE',
        'TICKET.REASSIGN',
        'TICKET.REOPEN'
  )
  AND NOT EXISTS (
        SELECT 1
        FROM TMS_ROLE_PERMISSIONS RP
        WHERE RP.ROLE_ID = R.ROLE_ID
          AND RP.PERMISSION_ID = P.PERMISSION_ID
  );


/* ================================================================
   8. CORE TICKET STATUS TRANSITIONS
   ================================================================ */

MERGE INTO TMS_STATUS_TRANSITIONS T
USING (
    SELECT
        'NEW'          FROM_STATUS,
        'ASSIGNED'     TO_STATUS,
        'TICKET'       REQUIRED_FUNCTION_CODE,
        'UPDATE'       REQUIRED_ACTION_CODE
    FROM DUAL

    UNION ALL

    SELECT
        'ASSIGNED',
        'IN PROGRESS',
        'TICKET',
        'UPDATE'
    FROM DUAL

    UNION ALL

    SELECT
        'IN PROGRESS',
        'PENDING',
        'TICKET',
        'UPDATE'
    FROM DUAL

    UNION ALL

    SELECT
        'PENDING',
        'IN PROGRESS',
        'TICKET',
        'UPDATE'
    FROM DUAL

    UNION ALL

    SELECT
        'IN PROGRESS',
        'RESOLVED',
        'TICKET',
        'UPDATE'
    FROM DUAL

    UNION ALL

    SELECT
        'RESOLVED',
        'CLOSED',
        'TICKET',
        'CLOSE'
    FROM DUAL

    UNION ALL

    SELECT
        'CLOSED',
        'REOPENED',
        'TICKET',
        'REOPEN'
    FROM DUAL

    UNION ALL

    SELECT
        'REOPENED',
        'ASSIGNED',
        'TICKET',
        'UPDATE'
    FROM DUAL
) S
ON (
       T.FROM_STATUS = S.FROM_STATUS
   AND T.TO_STATUS   = S.TO_STATUS
)

WHEN MATCHED THEN
    UPDATE SET
        T.REQUIRED_FUNCTION_CODE = S.REQUIRED_FUNCTION_CODE,
        T.REQUIRED_ACTION_CODE   = S.REQUIRED_ACTION_CODE,
        T.UPDATED_BY             = 'SYSTEM',
        T.UPDATED_DATE           = SYSTIMESTAMP

WHEN NOT MATCHED THEN
    INSERT (
        FROM_STATUS,
        TO_STATUS,
        REQUIRED_FUNCTION_CODE,
        REQUIRED_ACTION_CODE,
        CREATED_BY,
        CREATED_DATE,
        RECORD_VERSION
    )
    VALUES (
        S.FROM_STATUS,
        S.TO_STATUS,
        S.REQUIRED_FUNCTION_CODE,
        S.REQUIRED_ACTION_CODE,
        'SYSTEM',
        SYSTIMESTAMP,
        1
    );


/* ================================================================
   9. COMMIT
   ================================================================ */

COMMIT;