INSERT INTO tms_functions(function_code,function_name,created_by)
VALUES ('TICKET','Ticket Management','SYSTEM');

INSERT INTO tms_actions(action_code,action_name,created_by) VALUES ('CREATE','Create','SYSTEM');
INSERT INTO tms_actions(action_code,action_name,created_by) VALUES ('VIEW','View','SYSTEM');
INSERT INTO tms_actions(action_code,action_name,created_by) VALUES ('UPDATE','Update','SYSTEM');
INSERT INTO tms_actions(action_code,action_name,created_by) VALUES ('CLOSE','Close','SYSTEM');
INSERT INTO tms_actions(action_code,action_name,created_by) VALUES ('REASSIGN','Reassign','SYSTEM');
INSERT INTO tms_actions(action_code,action_name,created_by) VALUES ('REOPEN','Reopen','SYSTEM');

INSERT INTO tms_status_transitions(from_status,to_status,required_function_code,required_action_code,created_by)
VALUES ('NEW','ASSIGNED','TICKET','UPDATE','SYSTEM');
INSERT INTO tms_status_transitions VALUES (DEFAULT,'ASSIGNED','IN PROGRESS','TICKET','UPDATE','SYSTEM',SYSTIMESTAMP,NULL,NULL,1);
INSERT INTO tms_status_transitions VALUES (DEFAULT,'IN PROGRESS','PENDING','TICKET','UPDATE','SYSTEM',SYSTIMESTAMP,NULL,NULL,1);
INSERT INTO tms_status_transitions VALUES (DEFAULT,'PENDING','IN PROGRESS','TICKET','UPDATE','SYSTEM',SYSTIMESTAMP,NULL,NULL,1);
INSERT INTO tms_status_transitions VALUES (DEFAULT,'IN PROGRESS','RESOLVED','TICKET','UPDATE','SYSTEM',SYSTIMESTAMP,NULL,NULL,1);
INSERT INTO tms_status_transitions VALUES (DEFAULT,'RESOLVED','CLOSED','TICKET','CLOSE','SYSTEM',SYSTIMESTAMP,NULL,NULL,1);
INSERT INTO tms_status_transitions VALUES (DEFAULT,'CLOSED','REOPENED','TICKET','REOPEN','SYSTEM',SYSTIMESTAMP,NULL,NULL,1);
INSERT INTO tms_status_transitions VALUES (DEFAULT,'REOPENED','ASSIGNED','TICKET','UPDATE','SYSTEM',SYSTIMESTAMP,NULL,NULL,1);

COMMIT;
