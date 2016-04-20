mysql> show create table dbs\G
*************************** 1. row ***************************
       Table: dbs
Create Table: CREATE TABLE `dbs` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `srv_id` int(11) NOT NULL,
  `db_name` varchar(100) NOT NULL,
  `db_size_mb` int(11) DEFAULT NULL,
  `db_tables_cnt` int(11) DEFAULT NULL,
  `db_backup` char(1) NOT NULL DEFAULT '1',
  `timestamp` timestamp NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `unique_srv_db_pair` (`srv_id`,`db_name`)
) ENGINE=InnoDB AUTO_INCREMENT=211 DEFAULT CHARSET=latin1
1 row in set (0.00 sec)
