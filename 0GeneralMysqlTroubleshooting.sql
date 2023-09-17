-- SHOW ALL PROCESSES
show processlist;

-- SHOW HOSTS CACHE
select * from performance_schema.host_cache

-- TO FLUSH HOSTS and clear connections
flush hosts;


