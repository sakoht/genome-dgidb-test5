package Genome::Site::WUGC::AdministrationProject; 

use strict;
use warnings;

class Genome::Site::WUGC::AdministrationProject {
    table_name => '(select * from ADMINISTRATION_PROJECT@oltp) admin_project',
    id_by => [
        id => { is => 'Number', len => 10, column_name => 'PROJECT_ID' },
    ],
    has => [
        creation_event_id => { is => 'Number', column_name => 'CREATION_EVENT_ID' },
        priority => { is => 'Text', column_name => 'PRIORITY' },
        project_name => { is => 'Text', column_name => 'PROJECT_NAME' }
    ],
    has_optional => [
        parent_project_id => { is => 'Number', column_name => 'PARENT_PROJECT_ID' },
        status => { is => 'Text', column_name => 'STATUS' }
    ],
    doc => 'yet another table about projects',
    data_source => 'Genome::DataSource::GMSchema',
};


1;


#ADMINISTRATION_PROJECT  GSC::AdministrationProject  oltp    production
#
#    BACKGROUND        background        BLOB(2147483647) NULLABLE         
#    CREATION_EVENT_ID creation_event_id NUMBER(10)                (fk)    
#    OVERVIEW          overview          BLOB(2147483647) NULLABLE         
#    PARENT_PROJECT_ID parent_project_id NUMBER(10)       NULLABLE (fk)    
#    PRIORITY          priority          VARCHAR2(16)                      
#    PROJECT_ID        project_id        NUMBER(10)                (pk)    
#    PROJECT_NAME      project_name      VARCHAR2(100)             (unique)
#    PROJECT_UPDATE    project_update    BLOB(2147483647) NULLABLE         
#    STATUS            status            VARCHAR2(32)     NULLABLE  


