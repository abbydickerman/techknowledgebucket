--CHECK UPTIME
use master
go
select name, create_date from sys.databases where name='tempDB'

---- CHECK INDEX FRAG
SELECT dbschemas.[name] as 'Schema',
dbtables.[name] as 'Table',
dbindexes.[name] as 'Index',
indexstats.avg_fragmentation_in_percent,
indexstats.page_count
FROM sys.dm_db_index_physical_stats (DB_ID(), NULL, NULL, NULL, NULL) AS indexstats
INNER JOIN sys.tables dbtables on dbtables.[object_id] = indexstats.[object_id]
INNER JOIN sys.schemas dbschemas on dbtables.[schema_id] = dbschemas.[schema_id]
INNER JOIN sys.indexes AS dbindexes ON dbindexes.[object_id] = indexstats.[object_id]
AND indexstats.index_id = dbindexes.index_id
WHERE indexstats.database_id = DB_ID()
ORDER BY indexstats.avg_fragmentation_in_percent desc

-- SHOW CONNECTIONS
SELECT * FROM sys.dm_exec_connections

--Show queries currently running
SELECT      r.start_time [Start Time],session_ID [SPID],
            DB_NAME(database_id) [Database],
            SUBSTRING(t.text,(r.statement_start_offset/2)+1,
            CASE WHEN statement_end_offset=-1 OR statement_end_offset=0
            THEN (DATALENGTH(t.Text)-r.statement_start_offset/2)+1
            ELSE (r.statement_end_offset-r.statement_start_offset)/2+1
            END) [Executing SQL],
            Status,command,wait_type,wait_time,wait_resource,
            last_wait_type
FROM        sys.dm_exec_requests r
OUTER APPLY sys.dm_exec_sql_text(sql_handle) t
WHERE       session_id != @@SPID -- don't show this query
AND         session_id > 50 -- don't show system queries
AND DB_NAME(database_id) = 'R4W_Primary'
ORDER BY    r.start_time;


---CONNECTIONS BY DB
SELECT
    DB_NAME(dbid) as DBName,
    COUNT(dbid) as NumberOfConnections,
    loginame as LoginName
FROM
    sys.sysprocesses
WHERE
    dbid > 0
GROUP BY
    dbid, loginame

	SELECT
    COUNT(dbid) as TotalConnections
FROM
    sys.sysprocesses
WHERE
    dbid > 0

-- CHECK BLOCKED PROCESSES
SELECT  spid,
        sp.[status],
        loginame [Login],
        hostname,
        blocked BlkBy,
        sd.name DBName,
        cmd Command,
        cpu CPUTime,
        physical_io DiskIO,
        last_batch LastBatch,
        [program_name] ProgramName
FROM master.dbo.sysprocesses sp
JOIN master.dbo.sysdatabases sd ON sp.dbid = sd.dbid
ORDER BY SPID DESC;

--get CPU count used by SQL Server
SELECT @utilizedCpuCount = COUNT( * )
FROM sys.dm_os_schedulers
WHERE status = 'VISIBLE ONLINE' ;



--calculate the CPU usage by queries OVER a 5 sec interval 
SELECT @init_sum_cpu_time = SUM(cpu_time)
FROM sys.dm_exec_requests WAITFOR DELAY '00:00:05'SELECT CONVERT(DECIMAL(5,
         2),
         ((SUM(cpu_time) - @init_sum_cpu_time) / (@utilizedCpuCount * 5000.00)) * 100) AS [CPU FROM Queries AS Percent of Total CPU Capacity]
FROM sys.dm_exec_requests

--To identify queries responsible for current high-CPU activity
SELECT TOP 100 s.session_id,
           r.status,
           r.cpu_time,
           r.logical_reads,
           r.reads,
           r.writes,
           r.total_elapsed_time / (1000 * 60) 'Elaps M',
           SUBSTRING(st.TEXT, (r.statement_start_offset / 2) + 1,
           ((CASE r.statement_end_offset
                WHEN -1 THEN DATALENGTH(st.TEXT)
                ELSE r.statement_end_offset
            END - r.statement_start_offset) / 2) + 1) AS statement_text,
           COALESCE(QUOTENAME(DB_NAME(st.dbid)) + N'.' + QUOTENAME(OBJECT_SCHEMA_NAME(st.objectid, st.dbid)) 
           + N'.' + QUOTENAME(OBJECT_NAME(st.objectid, st.dbid)), '') AS command_text,
           r.command,
           s.login_name,
           s.host_name,
           s.program_name,
           s.last_request_end_time,
           s.login_time,
           r.open_transaction_count
FROM sys.dm_exec_sessions AS s
JOIN sys.dm_exec_requests AS r ON r.session_id = s.session_id CROSS APPLY sys.Dm_exec_sql_text(r.sql_handle) AS st
WHERE r.session_id != @@SPID
ORDER BY r.cpu_time DESC;

--second query to look into high cpu-usage--

select top 10 * 
from sys.dm_exec_session_wait_stats w
join sys.dm_exec_sessions s on s.session_id = w.session_id 
order by w.wait_time_ms desc



--To identify queries responsible for historical high-CPU activity
SELECT TOP 10 st.text AS batch_text,
    SUBSTRING(st.TEXT, (qs.statement_start_offset / 2) + 1, ((CASE qs.statement_end_offset WHEN - 1 THEN DATALENGTH(st.TEXT) ELSE qs.statement_end_offset END - qs.statement_start_offset) / 2) + 1) AS statement_text,
    (qs.total_worker_time / 1000) / qs.execution_count AS avg_cpu_time_ms,
    (qs.total_elapsed_time / 1000) / qs.execution_count AS avg_elapsed_time_ms,
    qs.total_logical_reads / qs.execution_count AS avg_logical_reads,
    (qs.total_worker_time / 1000) AS cumulative_cpu_time_all_executions_ms,
    (qs.total_elapsed_time / 1000) AS cumulative_elapsed_time_all_executions_ms
FROM sys.dm_exec_query_stats qs
CROSS APPLY sys.dm_exec_sql_text(sql_handle) st
ORDER BY(qs.total_worker_time / qs.execution_count) DESC;

--index use counts and fragmentation--
WITH fragmentation AS (
	SELECT S.name as 'Schema',
	T.name as 'Table',
	I.name as 'Index',
	DDIPS.avg_fragmentation_in_percent,
	DDIPS.page_count
	FROM sys.dm_db_index_physical_stats (DB_ID(), NULL, NULL, NULL, NULL) AS DDIPS
	INNER JOIN sys.tables T on T.object_id = DDIPS.object_id
	INNER JOIN sys.schemas S on T.schema_id = S.schema_id
	INNER JOIN sys.indexes I ON I.object_id = DDIPS.object_id
	AND DDIPS.index_id = I.index_id
	WHERE DDIPS.database_id = DB_ID()
	and I.name is not null
	AND DDIPS.avg_fragmentation_in_percent > 0
),
usage AS (
	SELECT   OBJECT_NAME(S.[OBJECT_ID]) AS [OBJECT NAME],
			 I.[NAME] AS [INDEX NAME],
			 USER_SEEKS,
			 USER_SCANS,
			 USER_LOOKUPS,
			 USER_UPDATES
	FROM     SYS.DM_DB_INDEX_USAGE_STATS AS S WITH (NOLOCK)
			 INNER JOIN SYS.INDEXES AS I
			   ON I.[OBJECT_ID] = S.[OBJECT_ID]
				  AND I.INDEX_ID = S.INDEX_ID
	WHERE    OBJECTPROPERTY(S.[OBJECT_ID],'IsUserTable') = 1
)

SELECT
	u.*,
	f.avg_fragmentation_in_percent,
	f.page_count
FROM fragmentation f
INNER JOIN usage u
	ON u.[OBJECT NAME] = f.[Table]
	AND u.[INDEX NAME] = f.[Index]

--sql_statistics--
IF Object_id('tempdb..#StatsInfo') IS NOT NULL
  DROP TABLE #statsinfo;
GO

IF Object_id('tempdb..#ColumnList') IS NOT NULL
  DROP TABLE #columnlist;
GO

DECLARE @object_id INT =NULL;

SELECT
  ss.[name] AS SchemaName,
  obj.[name] AS TableName,
  stat.[stats_id],
  stat.[name] AS StatisticsName,
  CASE
    WHEN stat.[auto_created] = 0
    AND stat.[user_created] = 0 THEN 'Index Statistic'
    WHEN stat.[auto_created] = 0
    AND stat.[user_created] = 1 THEN 'User Created'
    WHEN stat.[auto_created] = 1
    AND stat.[user_created] = 0  THEN 'Auto Created'
    WHEN stat.[auto_created] = 1
    AND stat.[user_created] = 1 THEN 'Updated stats available in Secondary'
  END AS StatisticType,
  CASE
    WHEN stat.[is_temporary] = 0 THEN 'Stats in DB'
    WHEN stat.[is_temporary] = 1 THEN 'Stats in Tempdb'
  END AS IsTemporary,
  CASE
    WHEN stat.[has_filter] = 1 THEN 'Filtered Index'
    WHEN stat.[has_filter] = 0 THEN 'No Filter'
  END AS IsFiltered,
  c.[name] AS ColumnName,
  stat.[filter_definition],
  sp.[last_updated],
  sp.[rows],
  sp.[rows_sampled],
  sp.[steps] AS HistorgramSteps,
  sp.[unfiltered_rows],
  sp.[modification_counter] AS RowsModified
INTO #statsinfo
FROM
  sys.[objects] AS obj
  INNER JOIN sys.[schemas] ss
    ON obj.[schema_id] = ss.[schema_id]
  INNER JOIN sys.[stats] stat
    ON stat.[object_id] = obj.[object_id]
  JOIN sys.[stats_columns] sc
    ON sc.[object_id] = stat.[object_id]
    AND sc.[stats_id] = stat.[stats_id]
  JOIN sys.columns c
    ON c.[object_id] = sc.[object_id]
    AND c.[column_id] = sc.[column_id]
  CROSS apply sys.Dm_db_stats_properties(stat.object_id, stat.stats_id) AS sp
WHERE
  ( obj.[is_ms_shipped] = 0
  AND obj.[object_id] = @object_id )
  OR ( obj.[is_ms_shipped] = 0 )
ORDER BY
  ss.[name],
  obj.[name],
  stat.[name];

SELECT
  t.[schemaname],
  t.[tablename],
  t.[stats_id],
  Stuff((SELECT ',' + s.[columnname]
FROM
  #statsinfo s
WHERE
  s.[schemaname] = t.[schemaname]
  AND s.[tablename] = t.[tablename]
  AND s.stats_id = t.stats_id
FOR xml path('')), 1, 1, '') AS ColumnList
INTO   #columnlist
FROM   #statsinfo AS t
GROUP BY
  t.[schemaname],
  t.[tablename],
  t.[stats_id];

SELECT DISTINCT
  SI.[schemaname],
  SI.[tablename],
  SI.[stats_id],
  SI.[statisticsname],
  SI.[statistictype],
  SI.[istemporary],
  CL.[columnlist] AS ColumnName,
  SI.[isfiltered],
  SI.[filter_definition],
  SI.[last_updated],
  SI.[rows],
  SI.[rows_sampled],
  SI.[historgramsteps],
  SI.[unfiltered_rows],
  SI.[rowsmodified]
FROM
  #statsinfo SI
  INNER JOIN #columnlist CL
  ON SI.[schemaname] = CL.[schemaname]
  AND SI.[tablename] = CL.[tablename]
  AND SI.[stats_id] = CL.[stats_id]
ORDER BY
  SI.[schemaname],
  SI.[tablename],
  SI.[statisticsname];
GO

--expensive queries with command text and plan--
SELECT TOP 20
    qs.sql_handle,
    qs.execution_count,
    qs.total_worker_time AS Total_CPU,
    total_CPU_inSeconds = --Converted from microseconds
        qs.total_worker_time/1000000,
    average_CPU_inSeconds = --Converted from microseconds
        (qs.total_worker_time/1000000) / qs.execution_count,
    qs.total_elapsed_time,
    total_elapsed_time_inSeconds = --Converted from microseconds
        qs.total_elapsed_time/1000000,
    st.text,
    qp.query_plan
FROM
    sys.dm_exec_query_stats AS qs
CROSS APPLY
    sys.dm_exec_sql_text(qs.sql_handle) AS st
CROSS APPLY
    sys.dm_exec_query_plan (qs.plan_handle) AS qp
ORDER BY
    qs.total_worker_time DESC;

select count(*) from MIMPORT;


--check if lock_escalation should be turned on--

select * from sys.dm_tran_locks where resource_database_id = 35;

--Disable Lock Escalation--
ALTER TABLE dbo.MIMPORT (LOCK_ESCALATION = DISABLE)

--Check for triggers--
INNER JOIN sys.objects o ON o.object_id = t.objects_id INNER JOIN sys.objects p ON p.object_id = o.parent_object_id WHERE t.[type] = 'TR'
SELECT * FROM sys.triggers t


--Find last queries executed by user
SELECT sdest.DatabaseName
    ,sdes.session_id
    ,sdes.[host_name]
    ,sdes.[program_name]
    ,sdes.client_interface_name
    ,sdes.login_name
    ,sdes.login_time
    ,sdes.nt_domain
    ,sdes.nt_user_name
    ,sdec.client_net_address
    ,sdec.local_net_address
    ,sdest.ObjName
    ,sdest.Query
FROM sys.dm_exec_sessions AS sdes
INNER JOIN sys.dm_exec_connections AS sdec ON sdec.session_id = sdes.session_id
CROSS APPLY (
    SELECT db_name(dbid) AS DatabaseName
        ,object_id(objectid) AS ObjName
        ,ISNULL((
                SELECT TEXT AS [processing-instruction(definition)]
                FROM sys.dm_exec_sql_text(sdec.most_recent_sql_handle)
                FOR XML PATH('')
                    ,TYPE
                ), '') AS Query

    FROM sys.dm_exec_sql_text(sdec.most_recent_sql_handle)
    ) sdest
where sdes.session_id <> @@SPID
--and sdes.nt_user_name = '' -- Put the username here !
ORDER BY sdec.session_id;

--