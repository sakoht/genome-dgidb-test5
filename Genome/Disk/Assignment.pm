package Genome::Disk::Assignment;

use strict;
use warnings;

class Genome::Disk::Assignment {
    table_name => "(select * from disk_volume_group\@oltp) assignment",
    id_by => [
              dg_id => {is => 'Number'},
              dv_id => {is => 'Number'},
          ],
    has => [
            group => {
                      is => 'Genome::Disk::Group',
                      id_by => 'dg_id',
                  },
            disk_group_name => { via => 'group' },
            user_name => { via => 'group' },
            group_name => { via => 'group' },
            subdirectory => { via => 'group' },
            volume => {
                       is => 'Genome::Disk::Volume',
                       id_by => 'dv_id',
                   },
            mount_path => { via => 'volume' },
            total_kb   => { via => 'volume' },
            unallocated_kb => { via => 'volume' },
            allocated_kb => {
                             calculate_from => ['total_kb','unallocated_kb'],
                             calculate => q|
                                  return ($total_kb - $unallocated_kb);
                              |,
                         },
            percent_used => {
                             calculate_from => ['total_kb','allocated_kb'],
                             calculate => q|
                                  return sprintf("%.2f", ( $allocated_kb / $total_kb ) * 100);
                              |,
                         },
            absolute_path => {
                              calculate_from => ['mount_path','subdirectory'],
                              calculate => q|
                                  return $mount_path .'/'. $subdirectory;
                              |,
                          },
        ],
    data_source => 'Genome::DataSource::GMSchema',
};

1;
