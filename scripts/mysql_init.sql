-- WorldApp 数据库初始化脚本
-- 以 root 执行：sudo mysql < scripts/mysql_init.sql
-- 创建库 all_in_one 与读写用户 world / world123（与 main.v 默认连接参数一致）

CREATE DATABASE IF NOT EXISTS all_in_one
  CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

CREATE USER IF NOT EXISTS 'world'@'localhost' IDENTIFIED BY 'world123';
CREATE USER IF NOT EXISTS 'world'@'127.0.0.1' IDENTIFIED BY 'world123';

GRANT SELECT, INSERT, UPDATE, DELETE, CREATE, DROP, INDEX, ALTER
  ON all_in_one.* TO 'world'@'localhost';
GRANT SELECT, INSERT, UPDATE, DELETE, CREATE, DROP, INDEX, ALTER
  ON all_in_one.* TO 'world'@'127.0.0.1';

FLUSH PRIVILEGES;
